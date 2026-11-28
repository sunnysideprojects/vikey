import AppKit
import SwiftUI
import ViKeyCore

/// What the settings window shows but does not own (macro file status, login item, the apps in
/// the fast-typing list) plus the actions it asks AppDelegate to run. Plain preferences are not
/// here: the views read and write UserDefaults (`@AppStorage`, same keys as `Settings`), and
/// AppDelegate applies every change it sees.
final class SettingsState: ObservableObject {
    @Published var macroPath: String?
    @Published var macroInfo = ""
    @Published var macroFailed = false
    @Published var macroEntries: [MacroEntry] = []
    @Published var macroWritable = false
    /// Read fine but in an encoding ViKey does not write (old single-byte file).
    @Published var macroReadOnly = false
    @Published var loginEnabled = false
    /// Bundle IDs in the fast-typing list: apps with a fix on, plus ones just added.
    @Published var fixApps: [String] = []

    var chooseMacroFile: () -> Void = {}
    var createMacroFile: () -> Void = {}
    /// Writes one edit; the callback gets a message to show, or nil when done (saved, or the user
    /// chose to keep what the file says).
    var saveMacro: (MacroEdit, @escaping (String?) -> Void) -> Void = { _, done in done(nil) }
    var showMacroBackups: () -> Void = {}
    var openMacroFile: () -> Void = {}
    var reloadMacroFile: () -> Void = {}
    var clearMacroFile: () -> Void = {}
    var setLogin: (Bool) -> Void = { _ in }
    var checkForUpdates: () -> Void = {}

    /// Keeps apps the user added but has not ticked yet, so their row does not vanish.
    func syncFixApps(with settings: Settings) {
        let on = settings.slowApps.union(settings.realKeyApps)
        fixApps = fixApps + on.subtracting(fixApps).sorted { AppInfo.name($0) < AppInfo.name($1) }
    }
}

enum AppInfo {
    static func name(_ id: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first,
           let name = app.localizedName { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return url.deletingPathExtension().lastPathComponent
        }
        return id
    }

    static func icon(_ id: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}

/// "Cài đặt ViKey": toolbar tabs (NSTabViewController) hosting one SwiftUI form each.
final class SettingsWindow: NSWindowController {
    private static var shared: SettingsWindow?

    static func show(state: SettingsState) {
        let controller = shared ?? SettingsWindow(state: state)
        shared = controller
        NSApp.activate(ignoringOtherApps: true)
        if controller.window?.isVisible == false { controller.window?.center() }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(state: SettingsState) {
        let tabs = RememberingTabs()
        tabs.tabStyle = .toolbar
        func add<V: View>(_ view: V, _ title: String, _ symbol: String) {
            let host = NSHostingController(rootView: view.environmentObject(state))
            host.sizingOptions = .preferredContentSize
            host.title = title  // the tab controller shows it as the window title
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add(TypingTab(), "Gõ phím", "keyboard")
        add(MacroTab(), "Gõ tắt", "text.badge.plus")
        add(CompatibilityTab(), "Tương thích", "wrench.and.screwdriver")
        add(GeneralTab(), "Chung", "gearshape")
        let last = UserDefaults.standard.integer(forKey: RememberingTabs.key)
        if tabs.tabViewItems.indices.contains(last) { tabs.selectedTabViewItemIndex = last }

        let window = ClosableWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Opens on the tab used last time.
private final class RememberingTabs: NSTabViewController {
    static let key = "settingsTab"

    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        UserDefaults.standard.set(selectedTabViewItemIndex, forKey: Self.key)
    }
}

/// ViKey has no main menu (menu bar app), so ⌘W and Esc are handled here.
private final class ClosableWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { performClose(nil) }
}

// MARK: - Tabs

private let formWidth: CGFloat = 540

/// Title with a secondary line under it (the grouped form style shows the second Text that way).
private struct Labelled: View {
    let title: String
    let detail: String
    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }
    var body: some View {
        Text(title)
        Text(detail)
    }
}

private struct TypingTab: View {
    @AppStorage("method") private var method: InputMethod = .telex
    @AppStorage("hotkey") private var hotkey: Hotkey = .ctrlShift
    @AppStorage("smartSwitch") private var smartSwitch = true
    @AppStorage("modernTone") private var modernTone = false
    @AppStorage("spellCheck") private var spellCheck = true
    @AppStorage("englishRestore") private var englishRestore = true
    @AppStorage("escRevert") private var escRevert = true
    @AppStorage("backspaceResume") private var backspaceResume = true

    var body: some View {
        Form {
            Section {
                Picker("Kiểu gõ", selection: $method) {
                    Text("Telex").tag(InputMethod.telex)
                    Text("VNI").tag(InputMethod.vni)
                }
                .pickerStyle(.segmented)
                Picker("Phím chuyển Việt/Anh", selection: $hotkey) {
                    ForEach(Hotkey.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(isOn: $smartSwitch) {
                    Labelled("Nhớ Việt/Anh theo từng ứng dụng", "Mỗi app giữ chế độ gõ lần cuối bạn chọn trong app đó.")
                }
            }
            Section("Dấu và chính tả") {
                Toggle(isOn: $modernTone) {
                    Labelled("Đặt dấu kiểu mới", "oà, oé, uý thay cho òa, óe, úy.")
                }
                Toggle(isOn: $spellCheck) {
                    Labelled("Kiểm tra chính tả", "Chỉ bỏ dấu khi chữ còn là tiếng Việt; gõ tesst ra test, windows giữ nguyên.")
                }
                Toggle(isOn: $englishRestore) {
                    Labelled("Trả lại từ không có trong từ điển",
                             "Telex: hết từ mà chữ không có trong từ điển tiếng Việt của macOS (lă, ýe, mỏe) "
                                 + "thì trả lại đúng các phím đã gõ (law, yes, more). Cần bật kiểm tra chính tả.")
                }
                .disabled(!spellCheck || method != .telex)
                Toggle(isOn: $escRevert) {
                    Labelled("Esc trả lại các phím đã gõ",
                             "Ngay sau một từ bị đổi (cả), bấm Esc để lấy lại car. Esc đó không đến được app; "
                                 + "bấm lần nữa nếu cần. Tắt nếu bạn dùng vim.")
                }
                Toggle(isOn: $backspaceResume) {
                    Labelled("Xoá lùi để sửa từ vừa gõ",
                             "Xoá dấu cách ngay sau một từ là gõ tiếp được từ đó: tiêng ⌫ s (VNI: 1) ra tiếng. "
                                 + "Tắt nếu app tự sửa chữ khi bạn gõ dấu cách (autocorrect).")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: formWidth, height: 538)
    }
}

private struct MacroTab: View {
    @EnvironmentObject private var state: SettingsState
    @AppStorage("macroEnabled") private var macroEnabled = true
    @State private var search = ""
    @State private var selection: String?
    @State private var editing: EditRequest?
    @State private var message: String?

    private struct EditRequest: Identifiable {
        let id = UUID()
        let original: MacroEntry?
    }

    private var shown: [MacroEntry] {
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return state.macroEntries }
        return state.macroEntries.filter { $0.key.localizedStandardContains(q) || $0.value.localizedStandardContains(q) }
    }

    private func entry(_ key: String?) -> MacroEntry? {
        key.flatMap { k in state.macroEntries.first { $0.key == k } }
    }

    private func edit(_ key: String?) {
        guard state.macroWritable, let e = entry(key) else { return }
        editing = EditRequest(original: e)
    }

    private func delete(_ key: String?) {
        guard state.macroWritable, let e = entry(key) else { return }
        state.saveMacro(.remove(key: e.key, expected: e.value)) { error in
            if let error { message = error } else if selection == e.key { selection = nil }
        }
    }

    private var settingsForm: some View {
        Form {
            Section {
                Toggle(isOn: $macroEnabled) {
                    Labelled("Bật gõ tắt", "Gõ phím tắt rồi bấm cách, Return hay dấu câu: dc → được, "
                                 + "Dc → Được. Dùng file ukmacro.txt của UniKey.")
                }
            }
            Section("File gõ tắt") {
                LabeledContent("File") {
                    if let path = state.macroPath {
                        Text(URL(fileURLWithPath: path).lastPathComponent).help(path)
                    } else {
                        Text("Chưa chọn").foregroundStyle(.secondary)
                    }
                }
                if state.macroPath != nil {
                    LabeledContent("Trạng thái") {
                        Text(state.macroInfo).foregroundStyle(state.macroFailed ? .red : .secondary)
                    }
                }
                HStack {
                    Button(state.macroPath == nil ? "Chọn file…" : "Chọn file khác…") { state.chooseMacroFile() }
                    if state.macroPath == nil {
                        Button("Tạo file mới…") { state.createMacroFile() }
                    }
                    Spacer()
                    if state.macroPath != nil {
                        Button("Mở file") { state.openMacroFile() }
                            .help("Mở bằng ứng dụng sửa văn bản mặc định (TextEdit)")
                        Button("Đọc lại") { state.reloadMacroFile() }
                        Button("Bỏ chọn") { state.clearMacroFile() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        // The list lives outside the Form: a Table inside a Form never gets the scroll events.
        .scrollDisabled(true)
        .frame(height: state.macroPath == nil ? 250 : 290)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Tìm", text: $search, prompt: Text("Tìm phím tắt hoặc nội dung"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
            Table(shown, selection: $selection) {
                TableColumn("Phím tắt", value: \.key).width(min: 60, ideal: 110, max: 180)
                TableColumn("Nội dung", value: \.value)
            }
            .tableStyle(.bordered(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: String.self) { keys in
                if state.macroWritable, let key = keys.first {
                    Button("Sửa…") { edit(key) }
                    Button("Xoá") { delete(key) }
                }
            } primaryAction: { keys in
                edit(keys.first)
            }
            .onDeleteCommand { delete(selection) }
            HStack(spacing: 8) {
                Button { editing = EditRequest(original: nil) } label: { Image(systemName: "plus") }
                    .help("Thêm gõ tắt")
                    .disabled(!state.macroWritable)
                Button { delete(selection) } label: { Image(systemName: "minus") }
                    .help("Xoá gõ tắt đang chọn")
                    .disabled(!state.macroWritable || entry(selection) == nil)
                Button("Sửa…") { edit(selection) }
                    .disabled(!state.macroWritable || entry(selection) == nil)
                Spacer()
                Button("Xem bản cũ") { state.showMacroBackups() }
                    .help("Mở thư mục chứa các bản cũ của file, chép ra trước mỗi lần lưu")
            }
            Text(!state.macroReadOnly
                 ? "Sửa ở đây là ghi thẳng vào file, giữ nguyên định dạng để UniKey trên Windows vẫn đọc được. "
                     + "Nếu file vừa bị sửa ở máy khác, ViKey hỏi trước khi ghi đè. Đừng để cửa sổ "
                     + "sửa gõ tắt của UniKey mở lâu: nó lưu lại cả file theo bản nó đang giữ."
                 : "File không phải UTF-8 hay UTF-16 nên ViKey chỉ đọc. Lưu lại file bằng UniKey "
                     + "(Unicode) để sửa được ở đây.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsForm
            if state.macroPath != nil { list }
        }
        .frame(width: formWidth, height: state.macroPath == nil ? 250 : 660)
        .sheet(item: $editing) { request in
            MacroEditor(original: request.original) { key in selection = key }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        }
    }
}

/// Sheet for adding or changing one abbreviation.
private struct MacroEditor: View {
    @EnvironmentObject private var state: SettingsState
    @Environment(\.dismiss) private var dismiss
    let original: MacroEntry?
    let saved: (String) -> Void
    @State private var key: String
    @State private var value: String
    @State private var error: String?
    @State private var saving = false

    init(original: MacroEntry?, saved: @escaping (String) -> Void) {
        self.original = original
        self.saved = saved
        _key = State(initialValue: original?.key ?? "")
        _value = State(initialValue: original?.value ?? "")
    }

    private func save() {
        if let p = MacroDocument.problem(key: key, value: value) {
            error = p
            return
        }
        let edit: MacroEdit = original.map { .update(key: $0.key, expected: $0.value, newKey: key, value: value) }
            ?? .add(key: key, value: value)
        saving = true
        state.saveMacro(edit) { message in
            saving = false
            if let message {
                error = message
            } else {
                saved(key.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping)
                dismiss()
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(original == nil ? "Thêm gõ tắt" : "Sửa gõ tắt").font(.headline)
            Form {
                TextField("Phím tắt", text: $key, prompt: Text("dc"))
                TextField("Nội dung", text: $value, prompt: Text("được"))
            }
            Text(error ?? "Phím tắt viết thường thì gõ hoa cũng được: Dc → Được, DC → ĐƯỢC.")
                .font(.callout)
                .foregroundStyle(error == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Huỷ") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Lưu") { save() }.keyboardShortcut(.defaultAction).disabled(saving)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct CompatibilityTab: View {
    @EnvironmentObject private var state: SettingsState
    @AppStorage("browserFix") private var browserFix = true
    @AppStorage("addressBarOnly") private var addressBarOnly = false

    var body: some View {
        Form {
            Section("Trình duyệt") {
                Toggle(isOn: $browserFix) {
                    Labelled("Sửa lỗi gợi ý trên thanh địa chỉ",
                             "Gõ thêm một ký tự đệm rồi xoá đi mỗi khi đổi chữ, để phím xoá không xoá nhầm gợi ý.")
                }
                Toggle(isOn: $addressBarOnly) {
                    Labelled("Chỉ dùng ở thanh địa chỉ, không dùng trong trang web",
                             "Hỏi macOS (qua Accessibility) ô đang gõ có nằm trong trang web không. Ít phím hơn; "
                                 + "trình duyệt có thể chậm đi một chút vì phải bật trợ năng.")
                }
                .disabled(!browserFix)
            }
            Section {
                if state.fixApps.isEmpty {
                    Text("Chưa có ứng dụng nào.").foregroundStyle(.secondary)
                }
                ForEach(state.fixApps, id: \.self) { id in
                    AppFixRow(id: id)
                }
                AddAppMenu()
            } header: {
                Text("Sửa lỗi mất chữ khi gõ nhanh")
            } footer: {
                Text("Chỉ bật cho app vẫn mất chữ khi gõ nhanh. Gõ chậm: nghỉ 4 ms sau mỗi phím ViKey gửi. "
                     + "Phím thật: chữ cuối của phần đổi (à trong là) đi trong chính phím vừa bấm.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: formWidth, height: 430)
    }
}

private struct AppFixRow: View {
    @EnvironmentObject private var state: SettingsState
    let id: String

    private func binding(_ key: ReferenceWritableKeyPath<Settings, Set<String>>) -> Binding<Bool> {
        Binding(
            get: { Settings.shared[keyPath: key].contains(id) },
            set: { on in
                state.objectWillChange.send()
                var apps = Settings.shared[keyPath: key]
                if on { apps.insert(id) } else { apps.remove(id) }
                Settings.shared[keyPath: key] = apps
            })
    }

    var body: some View {
        HStack {
            Image(nsImage: AppInfo.icon(id)).resizable().frame(width: 20, height: 20)
            Text(AppInfo.name(id)).help(id)
            Spacer()
            Toggle("Gõ chậm", isOn: binding(\.slowApps)).toggleStyle(.checkbox)
            Toggle("Phím thật", isOn: binding(\.realKeyApps)).toggleStyle(.checkbox)
            Button {
                state.fixApps.removeAll { $0 == id }
                Settings.shared.slowApps.remove(id)
                Settings.shared.realKeyApps.remove(id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Bỏ app này khỏi danh sách")
        }
    }
}

private struct AddAppMenu: View {
    @EnvironmentObject private var state: SettingsState

    private var running: [(id: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { (id: $0, name: app.localizedName ?? $0) } }
            .filter { $0.id != Bundle.main.bundleIdentifier && !state.fixApps.contains($0.id) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Menu("Thêm ứng dụng…") {
            ForEach(running, id: \.id) { app in
                Button(app.name) { add(app.id) }
            }
            Divider()
            Button("Chọn ứng dụng khác…") { chooseApp() }
        }
        .fixedSize()
    }

    private func add(_ id: String) {
        if !state.fixApps.contains(id) { state.fixApps.append(id) }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Chọn ứng dụng vẫn mất chữ khi gõ nhanh"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        add(id)
    }
}

private struct GeneralTab: View {
    @EnvironmentObject private var state: SettingsState
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "dev"
        return (info["CFBundleVersion"] as? String).map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        Form {
            Section {
                Toggle("Khởi động cùng macOS", isOn: Binding(get: { state.loginEnabled }, set: { state.setLogin($0) }))
                Toggle(isOn: $autoUpdateCheck) {
                    Labelled("Tự kiểm tra cập nhật",
                             "Mỗi ngày một lần. Có bản mới thì menu hiện một dòng; cài bằng một nút bấm, "
                                 + "giữ nguyên quyền Accessibility.")
                }
                LabeledContent("Phiên bản \(version)") {
                    Button("Kiểm tra ngay…") { state.checkForUpdates() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: formWidth, height: 172)
    }
}
