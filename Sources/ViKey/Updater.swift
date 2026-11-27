import AppKit
import Sparkle

/// In-app updates with Sparkle: it reads `appcast.xml` from the latest GitHub release (`SUFeedURL`),
/// downloads the zip, checks its EdDSA signature (`SUPublicEDKey`; `scripts/release.sh` signs) and
/// that the new app carries the same code signature as the running one, installs it and relaunches.
///
/// ViKey lives in the menu bar, so an update found by a scheduled check does not pop a window over
/// whatever the user is doing (Sparkle's "gentle reminders"): it shows as a menu line, and choosing
/// it (or "Kiểm tra cập nhật…") brings up Sparkle's window.
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    /// Version found by a background check that the user has not looked at yet.
    private(set) var pendingVersion: String?
    /// Called on the main thread when `pendingVersion` changes.
    var onChange: (() -> Void)?

    /// Only from a real app bundle: `swift run` has no Info.plist to update.
    func start() {
        guard controller == nil, Bundle.main.bundleURL.pathExtension == "app" else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    /// Sparkle checks once a day while this is on (stored by Sparkle itself).
    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != newValue else { return }
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    private func setPending(_ version: String?) {
        guard version != pendingVersion else { return }
        pendingVersion = version
        onChange?()
    }

    // MARK: - SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus  // e.g. right at launch; otherwise the menu line
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if !handleShowingUpdate { setPending(update.displayVersionString) }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        setPending(nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        setPending(nil)
    }
}
