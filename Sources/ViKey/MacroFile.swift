import Foundation
import ViKeyCore

/// Keeps a MacroTable in sync with a ukmacro.txt that may live in a synced folder (Google Drive,
/// iCloud, Dropbox) shared with UniKey on Windows. Read-only: ViKey never writes the file.
///
/// FSEvents does not reliably report changes that a sync client pulls in from another machine,
/// so the file's date and size are polled. All file access is off the main thread: reading a
/// cloud placeholder can block while it downloads, and the event tap runs on the main thread.
final class MacroFile {
    enum Status {
        case none
        case loaded(count: Int)
        case failed(String)
    }

    private(set) var url: URL?
    private(set) var status: Status = .none
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
            onChange?(MacroTable())
            return
        }
        reload(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.reload(force: false)
        }
        timer?.tolerance = 1
    }

    func reload(force: Bool) {
        guard let url else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let date = attrs?[.modificationDate] as? Date ?? .distantPast
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? -1
            if !force, let s = self.stamp, s.0 == date, s.1 == size { return }
            do {
                let data = try Data(contentsOf: url)
                let table = MacroTable(data: data)
                self.stamp = (date, size)
                DispatchQueue.main.async {
                    guard self.url == url else { return }
                    self.status = .loaded(count: table.count)
                    self.onChange?(table)
                }
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
}
