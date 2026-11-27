import AppKit
import ServiceManagement
import UniformTypeIdentifiers
import ViKeyCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private var statusItem: NSStatusItem!
    private var engine: Engine!
    private var keyTap: KeyTap!
    private var permissionTimer: Timer?
    private let macroFile = MacroFile()
    private let lexicon = VietnameseLexicon()
    private let secureInput = SecureInputMonitor()
    private let settingsState = SettingsState()
    private var autoUpdateRunning = false
    /// A typing test (test build only) owns the engine settings: stored preferences stay unapplied.
    private var testing = false
    private let updates = UpdateChecker(
        currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = Engine(method: settings.method, modernTone: settings.modernTone, spellCheck: settings.spellCheck)
        keyTap = KeyTap(engine: engine)
        keyTap.frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        keyTap.onToggle = { [weak self] in self?.toggle() }
        keyTap.isWord = { [lexicon] in lexicon.contains($0) }
        lexicon.load()
        macroFile.onChange = { [weak self] table in
            guard let self else { return }
            if let table { self.keyTap.macros = table }
            self.refreshUI()
        }
        updates.onChange = { [weak self] in self?.refreshUI() }
        wireSettingsWindow()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applySettings()
        // The settings window writes UserDefaults directly; apply whatever changed.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.applySettings() }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        secureInput.onChange = { [weak self] in
            // Keys typed while Secure Input was on never reached the tap: the word state is stale.
            self?.keyTap.resetWord()
            self?.refreshUI()
        }
        secureInput.start()

        startWhenTrusted()
        // `open -a ViKey --args --about`: open the About window at launch (for checking the layout).
        if CommandLine.arguments.contains("--about") { AboutWindow.show() }
        // `--settings`: open the settings window at launch.
        if CommandLine.arguments.contains("--settings") { showSettings() }
        // `--check-update`: run the manual check at launch (for checking the dialog).
        if CommandLine.arguments.contains("--check-update") { checkForUpdates() }
        #if TYPING_TEST
        if let options = TypingTest.options(from: CommandLine.arguments) { runTypingTest(options) }
        #endif
    }

    #if TYPING_TEST
    /// `--typing-test cases.tsv --out results.tsv`: type the cases through the tap, write the
    /// results, quit. Settings are forced in memory only (defaults, macros off), never stored.
    private func runTypingTest(_ options: TypingTest.Options) {
        testing = true
        let test = TypingTest(options: options)
        test.status = { [unowned self] in (keyTap.isRunning, lexicon.isReady) }
        test.prepare = { [unowned self] method in
            engine.method = method
            engine.modernTone = false
            engine.spellCheck = true
            keyTap.enabled = true
            keyTap.englishRestore = true
            keyTap.escRevert = true
            keyTap.backspaceResume = true
            keyTap.macroEnabled = false
            keyTap.resetWord()
        }
        test.run { failures in exit(failures == 0 ? 0 : 1) }
    }
    #endif

    /// Pushes the stored preferences into the engine and the tap. Runs at launch and after every
    /// UserDefaults change (menu or settings window), so it only acts on what differs.
    private func applySettings() {
        guard !testing else { return }
        var wordStale = false
        if engine.method != settings.method {
            engine.method = settings.method
            wordStale = true
        }
        if engine.spellCheck != settings.spellCheck {
            engine.spellCheck = settings.spellCheck
            wordStale = true
        }
        if keyTap.macroEnabled != settings.macroEnabled {
            keyTap.macroEnabled = settings.macroEnabled
            wordStale = true
        }
        if wordStale { keyTap.resetWord() }
        engine.modernTone = settings.modernTone
        keyTap.enabled = settings.enabled
        keyTap.hotkey = settings.hotkey
        keyTap.englishRestore = settings.englishRestore
        keyTap.escRevert = settings.escRevert
        keyTap.backspaceResume = settings.backspaceResume
        keyTap.browserFix = settings.browserFix
        keyTap.addressBarOnly = settings.addressBarOnly
        keyTap.slowApps = settings.slowApps
        keyTap.realKeyApps = settings.realKeyApps
        if macroFile.url?.path != settings.macroPath {
            macroFile.watch(settings.macroPath.map { URL(fileURLWithPath: $0) })
        }
        if settings.autoUpdateCheck != autoUpdateRunning {
            autoUpdateRunning = settings.autoUpdateCheck
            if autoUpdateRunning { updates.startAutomatic() } else { updates.stopAutomatic() }
        }
        refreshUI()
    }

    // MARK: - Accessibility

    private func startWhenTrusted() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startTap()
            return
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.startTap()
        }
    }

    private func startTap() {
        if !keyTap.start() {
            let alert = NSAlert()
            alert.messageText = "ViKey không bắt được bàn phím"
            alert.informativeText = "Vào System Settings → Privacy & Security → Accessibility, xoá ViKey khỏi danh sách rồi thêm lại, sau đó mở lại app."
            alert.runModal()
        }
        refreshUI()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - State

    private func toggle() {
        setEnabled(!settings.enabled)
    }

    private func setEnabled(_ on: Bool, remember: Bool = true) {
        settings.enabled = on
        keyTap.enabled = on
        keyTap.resetWord()
        if remember, settings.smartSwitch, let id = keyTap.frontBundleID {
            var states = settings.appStates
            states[id] = on
            settings.appStates = states
        }
        refreshUI()
    }

    @objc private func appActivated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        keyTap.frontBundleID = app?.bundleIdentifier
        keyTap.resetWord()
        if !testing, settings.smartSwitch, let id = app?.bundleIdentifier, let saved = settings.appStates[id],
           saved != settings.enabled {
            setEnabled(saved, remember: false)
        }
    }

    // MARK: - Menu

    private func refreshUI() {
        if let button = statusItem.button {
            let on = settings.enabled
            let locked = secureInput.isOn
            button.attributedTitle = NSAttributedString(
                string: on ? "V" : "E",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14, weight: .bold),
                    // Greyed while Secure Input blocks the tap: ViKey sees no keys.
                    .foregroundColor: locked ? NSColor.secondaryLabelColor : on ? NSColor.systemRed : NSColor.labelColor,
                ])
            button.image = locked ? Self.lockImage : nil
            button.imagePosition = .imageLeading
            if locked {
                button.toolTip = "ViKey tạm dừng: \(secureInputHolder) đang bật Secure Input"
            } else {
                button.toolTip = on ? "ViKey: Tiếng Việt (\(settings.method == .telex ? "Telex" : "VNI"))" : "ViKey: English"
            }
        }
        statusItem.menu = buildMenu()
        updateSettingsState()
    }

    private static let lockImage: NSImage? = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secure Input")?
        .withSymbolConfiguration(.init(pointSize: 10, weight: .bold))

    private var secureInputHolder: String { secureInput.holder ?? "một ứng dụng" }

    private func item(_ title: String, _ action: Selector?, checked: Bool = false, tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        i.state = checked ? .on : .off
        i.tag = tag
        return i
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        if secureInput.isOn {
            let info = NSMenuItem(title: "🔒 Tạm dừng: \(secureInputHolder) đang bật Secure Input", action: nil, keyEquivalent: "")
            info.toolTip = "Khi ô mật khẩu hoặc Secure Keyboard Entry (Terminal, iTerm) đang bật, macOS không cho "
                + "bộ gõ nào nhận phím. ViKey tự chạy lại khi nó tắt."
            menu.addItem(info)
        }
        if let release = updates.available {
            menu.addItem(item("⬆️ Đã có ViKey \(release.version) — mở trang tải về…", #selector(openReleasePage)))
        }
        if secureInput.isOn || updates.available != nil { menu.addItem(.separator()) }
        menu.addItem(item("Gõ tiếng Việt (\(settings.hotkey.symbol))", #selector(menuToggle), checked: settings.enabled))
        menu.addItem(.separator())
        menu.addItem(item("Telex", #selector(chooseTelex), checked: settings.method == .telex))
        menu.addItem(item("VNI", #selector(chooseVNI), checked: settings.method == .vni))
        menu.addItem(.separator())
        menu.addItem(toolsMenu())
        menu.addItem(.separator())
        if !keyTap.isRunning {
            menu.addItem(item("⚠️ Cấp quyền Accessibility…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }
        let prefs = item("Cài đặt…", #selector(showSettings))
        prefs.keyEquivalent = ","
        menu.addItem(prefs)
        menu.addItem(item("Kiểm tra cập nhật…", #selector(checkForUpdates)))
        menu.addItem(item("Giới thiệu ViKey", #selector(showAbout)))
        let quitItem = item("Thoát ViKey", #selector(quit))
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)
        return menu
    }

    // MARK: - Settings window

    @objc private func showSettings() { SettingsWindow.show(state: settingsState) }

    private func wireSettingsWindow() {
        settingsState.chooseMacroFile = { [weak self] in self?.chooseMacroFile() }
        settingsState.openMacroFile = { [weak self] in
            if let url = self?.macroFile.url { NSWorkspace.shared.open(url) }
        }
        settingsState.reloadMacroFile = { [weak self] in self?.macroFile.reload(force: true) }
        settingsState.clearMacroFile = { [weak self] in self?.settings.macroPath = nil }
        settingsState.setLogin = { [weak self] on in self?.setLaunchAtLogin(on) }
        settingsState.checkForUpdates = { [weak self] in self?.checkForUpdates() }
    }

    private func updateSettingsState() {
        let state = settingsState
        state.macroPath = macroFile.url?.path
        switch macroFile.status {
        case .none: state.macroInfo = "Đang đọc…"; state.macroFailed = false
        case .loaded(let n): state.macroInfo = "\(n) mục"; state.macroFailed = false
        case .failed: state.macroInfo = "Không đọc được file"; state.macroFailed = true
        }
        state.loginEnabled = SMAppService.mainApp.status == .enabled
        state.syncFixApps(with: settings)
    }

    // MARK: - Clipboard tools

    private static let toolTitles: [(TextTool, String)] = [
        (.removeAccents, "Bỏ dấu (Tiếng Việt → Tieng Viet)"),
        (.upper, "CHỮ HOA"),
        (.lower, "chữ thường"),
        (.titleCase, "Viết Hoa Đầu Mỗi Từ"),
        (.fromTCVN3, "TCVN3 (ABC) → Unicode"),
        (.fromVNI, "VNI Windows → Unicode"),
        (.composeNFC, "Unicode tổ hợp → Unicode dựng sẵn"),
    ]

    private func toolsMenu() -> NSMenuItem {
        let top = NSMenuItem(title: "Chuyển văn bản trong clipboard", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let hint = NSMenuItem(title: "Sao chép (⌘C), chọn lệnh, rồi dán (⌘V)", action: nil, keyEquivalent: "")
        sub.addItem(hint)
        sub.addItem(.separator())
        for (idx, (tool, title)) in Self.toolTitles.enumerated() {
            if tool == .fromTCVN3 { sub.addItem(.separator()) }
            sub.addItem(item(title, #selector(runTool(_:)), tag: idx))
        }
        top.submenu = sub
        return top
    }

    /// Converts the text on the clipboard in place (plain text; formatting is dropped).
    /// Beeps when there is no text or nothing changed.
    @objc private func runTool(_ sender: NSMenuItem) {
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string) else {
            NSSound.beep()
            return
        }
        let result = Self.toolTitles[sender.tag].0.apply(text)
        guard result != text else {
            NSSound.beep()
            return
        }
        pb.clearContents()
        pb.setString(result, forType: .string)
    }

    // MARK: - Abbreviations (gõ tắt)

    private func chooseMacroFile() {
        let panel = NSOpenPanel()
        panel.title = "Chọn file gõ tắt của UniKey"
        panel.message = "Chọn ukmacro.txt (có thể nằm trong Google Drive để dùng chung với UniKey)."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text]
        let cloud = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage")
        if let current = macroFile.url {
            panel.directoryURL = current.deletingLastPathComponent()
        } else if FileManager.default.fileExists(atPath: cloud.path) {
            panel.directoryURL = cloud
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.macroEnabled = true
        settings.macroPath = url.path  // applySettings starts watching it
    }

    @objc private func menuToggle() { toggle() }

    @objc private func chooseTelex() { settings.method = .telex }
    @objc private func chooseVNI() { settings.method = .vni }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSAlert(error: error).runModal()
        }
        refreshUI()
    }

    // MARK: - Updates

    @objc private func openReleasePage() {
        NSWorkspace.shared.open(updates.available?.page ?? UpdateChecker.releasesPage)
    }

    @objc private func checkForUpdates() {
        updates.check { [weak self] outcome in
            let alert = NSAlert()
            switch outcome {
            case .available(let release):
                alert.messageText = "Đã có ViKey \(release.version)"
                alert.informativeText = "Bạn đang dùng bản \(self?.updates.current?.description ?? "?"). "
                    + "Tải file zip trên trang phát hành, giải nén rồi thay ViKey.app trong Applications. "
                    + "Sau khi thay, bật lại quyền Accessibility cho ViKey."
                alert.addButton(withTitle: "Mở trang tải về")
                alert.addButton(withTitle: "Để sau")
            case .upToDate(let current):
                alert.messageText = "ViKey đã là bản mới nhất"
                alert.informativeText = "Phiên bản \(current)."
            case .failed(let reason):
                alert.alertStyle = .warning
                alert.messageText = "Không kiểm tra được cập nhật"
                alert.informativeText = reason
            }
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn, case .available(let release) = outcome {
                NSWorkspace.shared.open(release.page)
            }
        }
    }

    @objc private func showAbout() { AboutWindow.show() }

    @objc private func quit() { NSApp.terminate(nil) }
}
