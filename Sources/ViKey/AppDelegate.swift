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
    private let secureInput = SecureInputMonitor()
    private let updates = UpdateChecker(
        currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine = Engine(method: settings.method, modernTone: settings.modernTone, spellCheck: settings.spellCheck)
        keyTap = KeyTap(engine: engine)
        keyTap.enabled = settings.enabled
        keyTap.hotkey = settings.hotkey
        keyTap.browserFix = settings.browserFix
        keyTap.frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        keyTap.onToggle = { [weak self] in self?.toggle() }
        keyTap.macroEnabled = settings.macroEnabled
        macroFile.onChange = { [weak self] table in
            guard let self else { return }
            if let table { self.keyTap.macros = table }
            self.refreshUI()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshUI()

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
        macroFile.watch(settings.macroPath.map { URL(fileURLWithPath: $0) })
        // `open -a ViKey --args --about`: open the About window at launch (for checking the layout).
        if CommandLine.arguments.contains("--about") { AboutWindow.show() }

        updates.onChange = { [weak self] in self?.refreshUI() }
        if settings.autoUpdateCheck { updates.startAutomatic() }
        // `--check-update`: run the manual check at launch (for checking the dialog).
        if CommandLine.arguments.contains("--check-update") { checkForUpdates() }
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
        if settings.smartSwitch, let id = app?.bundleIdentifier, let saved = settings.appStates[id],
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
        menu.addItem(item("Đặt dấu kiểu mới (oà, uý)", #selector(toggleModern), checked: settings.modernTone))
        menu.addItem(item("Kiểm tra chính tả, khôi phục từ tiếng Anh", #selector(toggleSpell), checked: settings.spellCheck))
        menu.addItem(item("Nhớ Việt/Anh theo từng ứng dụng", #selector(toggleSmart), checked: settings.smartSwitch))
        menu.addItem(item("Sửa lỗi gợi ý trên thanh địa chỉ trình duyệt", #selector(toggleBrowserFix), checked: settings.browserFix))

        let hk = NSMenuItem(title: "Phím chuyển Việt/Anh", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (idx, h) in Hotkey.allCases.enumerated() {
            sub.addItem(item(h.title, #selector(chooseHotkey(_:)), checked: settings.hotkey == h, tag: idx))
        }
        hk.submenu = sub
        menu.addItem(hk)
        menu.addItem(macroMenu())

        menu.addItem(item("Khởi động cùng macOS", #selector(toggleLogin), checked: SMAppService.mainApp.status == .enabled))
        menu.addItem(item("Tự kiểm tra cập nhật", #selector(toggleAutoUpdate), checked: settings.autoUpdateCheck))
        menu.addItem(.separator())
        if !keyTap.isRunning {
            menu.addItem(item("⚠️ Cấp quyền Accessibility…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }
        menu.addItem(item("Kiểm tra cập nhật…", #selector(checkForUpdates)))
        menu.addItem(item("Giới thiệu ViKey", #selector(showAbout)))
        menu.addItem(item("Thoát ViKey", #selector(quit)))
        return menu
    }

    // MARK: - Abbreviations (gõ tắt)

    private func macroMenu() -> NSMenuItem {
        var title = "Gõ tắt"
        if settings.macroEnabled, case .loaded(let n) = macroFile.status { title += " (\(n))" }
        let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.addItem(item("Bật gõ tắt", #selector(toggleMacro), checked: settings.macroEnabled))
        sub.addItem(.separator())
        sub.addItem(item("Chọn file gõ tắt (ukmacro.txt)…", #selector(chooseMacroFile)))
        if let url = macroFile.url {
            sub.addItem(item("Mở file để sửa", #selector(openMacroFile)))
            sub.addItem(item("Đọc lại file", #selector(reloadMacroFile)))
            sub.addItem(item("Bỏ chọn file", #selector(clearMacroFile)))
            sub.addItem(.separator())
            let info: String
            switch macroFile.status {
            case .none: info = url.lastPathComponent
            case .loaded(let n): info = "\(url.lastPathComponent): \(n) mục"
            case .failed: info = "⚠️ Không đọc được \(url.lastPathComponent)"
            }
            let i = NSMenuItem(title: info, action: nil, keyEquivalent: "")
            i.toolTip = url.path
            sub.addItem(i)
        } else {
            sub.addItem(.separator())
            sub.addItem(NSMenuItem(title: "Chưa chọn file", action: nil, keyEquivalent: ""))
        }
        top.submenu = sub
        return top
    }

    @objc private func toggleMacro() {
        settings.macroEnabled.toggle()
        keyTap.macroEnabled = settings.macroEnabled
        keyTap.resetWord()
        refreshUI()
    }

    @objc private func chooseMacroFile() {
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
        settings.macroPath = url.path
        if !settings.macroEnabled {
            settings.macroEnabled = true
            keyTap.macroEnabled = true
        }
        macroFile.watch(url)
        refreshUI()
    }

    @objc private func openMacroFile() {
        if let url = macroFile.url { NSWorkspace.shared.open(url) }
    }

    @objc private func reloadMacroFile() { macroFile.reload(force: true) }

    @objc private func clearMacroFile() {
        settings.macroPath = nil
        macroFile.watch(nil)
        refreshUI()
    }

    @objc private func menuToggle() { toggle() }

    @objc private func chooseTelex() { setMethod(.telex) }
    @objc private func chooseVNI() { setMethod(.vni) }
    private func setMethod(_ m: InputMethod) {
        settings.method = m
        engine.method = m
        keyTap.resetWord()
        refreshUI()
    }

    @objc private func toggleModern() {
        settings.modernTone.toggle()
        engine.modernTone = settings.modernTone
        refreshUI()
    }

    @objc private func toggleSpell() {
        settings.spellCheck.toggle()
        engine.spellCheck = settings.spellCheck
        keyTap.resetWord()
        refreshUI()
    }

    @objc private func toggleSmart() {
        settings.smartSwitch.toggle()
        refreshUI()
    }

    @objc private func toggleBrowserFix() {
        settings.browserFix.toggle()
        keyTap.browserFix = settings.browserFix
        refreshUI()
    }

    @objc private func chooseHotkey(_ sender: NSMenuItem) {
        let h = Hotkey.allCases[sender.tag]
        settings.hotkey = h
        keyTap.hotkey = h
        refreshUI()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        refreshUI()
    }

    // MARK: - Updates

    @objc private func toggleAutoUpdate() {
        settings.autoUpdateCheck.toggle()
        if settings.autoUpdateCheck { updates.startAutomatic() } else { updates.stopAutomatic() }
        refreshUI()
    }

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
