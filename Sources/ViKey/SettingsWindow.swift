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
    @Published var loginEnabled = false
    /// Bundle IDs in the fast-typing list: apps with a fix on, plus ones just added.
    @Published var fixApps: [String] = []

    var chooseMacroFile: () -> Void = {}
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
            }
        }
        .formStyle(.grouped)
        .frame(width: formWidth, height: 462)
    }
}

private struct MacroTab: View {
    @EnvironmentObject private var state: SettingsState
    @AppStorage("macroEnabled") private var macroEnabled = true

    var body: some View {
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
                    Spacer()
                    if state.macroPath != nil {
                        Button("Mở để sửa") { state.openMacroFile() }
                        Button("Đọc lại") { state.reloadMacroFile() }
                        Button("Bỏ chọn") { state.clearMacroFile() }
                    }
                }
                Text("File có thể nằm trong Google Drive hay iCloud để dùng chung với UniKey trên Windows. "
                     + "ViKey chỉ đọc, tự đọc lại khi file đổi.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: formWidth, height: 340)
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
                    Labelled("Tự kiểm tra cập nhật", "Hỏi GitHub mỗi ngày một lần. ViKey không tự tải hay cài.")
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
