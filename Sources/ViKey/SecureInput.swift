import AppKit
import Carbon

/// Watches macOS Secure Input. While any app holds it (a focused password field, Terminal/iTerm's
/// Secure Keyboard Entry, some password managers), event taps get no keystrokes, so ViKey cannot type.
/// macOS posts no notification for it, so it is polled; the check itself is a cheap flag read.
final class SecureInputMonitor {
    private(set) var isOn = false
    /// Name of the app holding it, when macOS reports one (the session's kCGSSessionSecureInputPID,
    /// which names the responsible GUI app).
    private(set) var holder: String?
    /// Called on the main thread when `isOn` or `holder` changes.
    var onChange: (() -> Void)?

    private var timer: Timer?

    func start() {
        check()
        // Default run loop mode only: no updates (and no menu rebuild) while the menu is open.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
        timer?.tolerance = 0.5
    }

    private func check() {
        let on = IsSecureEventInputEnabled()
        let name = on ? Self.holderName() : nil
        guard on != isOn || name != holder else { return }
        isOn = on
        holder = name
        onChange?()
    }

    private static func holderName() -> String? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value, pid > 0
        else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }
}
