import Foundation
import ViKeyCore

/// Keeps a MacroTable in sync with a ukmacro.txt that may live in a synced folder (Google Drive,
/// iCloud, Dropbox) shared with UniKey on Windows, and writes the editor's changes back.
///
/// FSEvents does not reliably report changes that a sync client pulls in from another machine,
/// so the file's date and size are polled. All file access is off the main thread: reading a
/// cloud placeholder can block while it downloads, and the event tap runs on the main thread.
///
/// Writing never trusts what was read earlier: each edit re-reads the file inside a coordinated
/// write (NSFileCoordinator, which the File Provider sync clients take part in), applies the one
/// change to the lines on disk, and checks the value the user saw is still there (else: conflict).
/// The file is overwritten in place, not replaced by a renamed temp file, so the sync client keeps
/// it as the same item (Google Drive tracks it by an extended attribute). The old bytes are copied
/// to `backupFolder` first.
final class MacroFile {
    enum Status {
        case none
        case loaded(count: Int)
        case failed(String)
    }

    enum WriteResult {
        case saved
        case conflict(current: String?)
        case invalid(String)
        case failed(String)
    }

    static let backupFolder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ViKey/Gõ tắt cũ", isDirectory: true)
    private static let backupsKept = 30

    private(set) var url: URL?
    private(set) var status: Status = .none
    /// Entries of the last good read, for the editor.
    private(set) var entries: [MacroEntry] = []
    private(set) var isWritable = false
    /// Called on the main thread after each read. A new table, or nil when the file could not be
    /// read (offline, mid-sync): then the last good table stays in use and only `status` changed.
    var onChange: ((MacroTable?) -> Void)?

    private let queue = DispatchQueue(label: "vikey.macrofile", qos: .utility)
    private var timer: Timer?
    private var stamp: (Date, Int)?  // touched only on `queue`

    func watch(_ url: URL?) {
        self.url = url
        timer?.invalidate()
        timer = nil
        queue.async { self.stamp = nil }
        guard url != nil else {
            status = .none
            entries = []
            isWritable = false
            onChange?(MacroTable())
            return
        }
        reload(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.reload(force: false)
        }
        timer?.tolerance = 1
    }

    private static func stamp(of url: URL) -> (Date, Int) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.modificationDate] as? Date ?? .distantPast, (attrs?[.size] as? NSNumber)?.intValue ?? -1)
    }

    func reload(force: Bool) {
        guard let url else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let stamp = Self.stamp(of: url)
            if !force, let s = self.stamp, s.0 == stamp.0, s.1 == stamp.1 { return }
            do {
                let doc = MacroDocument(data: try Data(contentsOf: url))
                self.stamp = stamp
                self.publish(doc, for: url)
            } catch {
                // Retry on the next tick; keep the previous table meanwhile.
                self.stamp = nil
                let message = (error as NSError).localizedDescription
                DispatchQueue.main.async {
                    guard self.url == url else { return }
                    self.status = .failed(message)
                    self.onChange?(nil)
                }
            }
        }
    }

    /// Called on `queue`.
    private func publish(_ doc: MacroDocument, for url: URL) {
        let table = doc.table
        let entries = doc.entries
        let writable = doc.isWritable
        DispatchQueue.main.async {
            guard self.url == url else { return }
            self.status = .loaded(count: table.count)
            self.entries = entries
            self.isWritable = writable
            self.onChange?(table)
        }
    }

    /// Writes one edit to the file as it is now on disk. `done` runs on the main thread.
    func write(_ edit: MacroEdit, force: Bool, done: @escaping (WriteResult) -> Void) {
        guard let url else { return done(.failed("Chưa chọn file.")) }
        queue.async { [weak self] in
            guard let self else { return }
            let result = Self.write(edit, force: force, to: url) { doc in self.publish(doc, for: url) }
            self.stamp = Self.stamp(of: url)
            DispatchQueue.main.async { done(result) }
        }
    }

    /// Creates a new, empty file the way UniKey writes one. Fails if the file exists.
    static func create(at url: URL) throws {
        let data = MacroDocument.newFile().data()
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordError) { u in
            do { try data.write(to: u, options: .withoutOverwriting) } catch { writeError = error }
        }
        if let e = coordError ?? writeError { throw e }
    }

    private static func write(_ edit: MacroEdit, force: Bool, to url: URL,
                              published: (MacroDocument) -> Void) -> WriteResult {
        var result = WriteResult.failed("")
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordError) { u in
            do {
                let old = try Data(contentsOf: u)
                var doc = MacroDocument(data: old)
                switch doc.apply(edit, force: force) {
                case .unchanged:
                    result = .saved
                    published(doc)
                    return
                case let .conflict(current):
                    result = .conflict(current: current)
                    published(doc)  // the editor shows what the file says now
                    return
                case let .invalid(message):
                    result = .invalid(message)
                    return
                case .applied:
                    break
                }
                let new = doc.data()
                try backUp(old, of: url)
                // In place: same inode and extended attributes (the sync client's item ID).
                let handle = try FileHandle(forWritingTo: u)
                defer { try? handle.close() }
                try handle.seek(toOffset: 0)
                try handle.write(contentsOf: new)
                try handle.truncate(atOffset: UInt64(new.count))
                try handle.synchronize()
                guard try Data(contentsOf: u) == new else {
                    result = .failed("Đọc lại không khớp với nội dung vừa ghi.")
                    return
                }
                result = .saved
                published(doc)
            } catch {
                result = .failed((error as NSError).localizedDescription)
            }
        }
        if let coordError { return .failed(coordError.localizedDescription) }
        return result
    }

    /// Copies the bytes about to be overwritten to the backup folder; keeps the newest ones.
    private static func backUp(_ data: Data, of url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = url.deletingPathExtension().lastPathComponent + " " + f.string(from: Date()) + ".txt"
        var target = backupFolder.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: target.path) {
            target = backupFolder.appendingPathComponent(name.replacingOccurrences(of: ".txt", with: " \(n).txt"))
            n += 1
        }
        try data.write(to: target)
        let old = (try? fm.contentsOfDirectory(at: backupFolder, includingPropertiesForKeys: [.creationDateKey]))?
            .filter { $0.pathExtension == "txt" }
            .map { ($0, (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .map(\.0) ?? []
        for url in old.dropFirst(backupsKept) { try? fm.removeItem(at: url) }
    }
}
