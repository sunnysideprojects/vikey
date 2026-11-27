import CoreGraphics
import Foundation
import ViKeyCore

enum Hotkey: String, CaseIterable {
    case ctrlShift, cmdShift, optShift, ctrlOpt

    var flags: CGEventFlags {
        switch self {
        case .ctrlShift: return [.maskControl, .maskShift]
        case .cmdShift: return [.maskCommand, .maskShift]
        case .optShift: return [.maskAlternate, .maskShift]
        case .ctrlOpt: return [.maskControl, .maskAlternate]
        }
    }

    var title: String {
        switch self {
        case .ctrlShift: return "⌃ Control + ⇧ Shift"
        case .cmdShift: return "⌘ Command + ⇧ Shift"
        case .optShift: return "⌥ Option + ⇧ Shift"
        case .ctrlOpt: return "⌃ Control + ⌥ Option"
        }
    }

    var symbol: String {
        switch self {
        case .ctrlShift: return "⌃⇧"
        case .cmdShift: return "⌘⇧"
        case .optShift: return "⌥⇧"
        case .ctrlOpt: return "⌃⌥"
        }
    }
}

/// UserDefaults-backed preferences. The settings window binds the same keys with `@AppStorage`;
/// the defaults are registered here so both sides agree on them.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            "enabled": true, "method": InputMethod.telex.rawValue, "modernTone": false, "spellCheck": true,
            "englishRestore": true, "escRevert": true, "smartSwitch": true, "browserFix": true,
            "addressBarOnly": false, "hotkey": Hotkey.ctrlShift.rawValue, "macroEnabled": true,
            "autoUpdateCheck": true,
        ])
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        d.object(forKey: key) as? Bool ?? fallback
    }

    var enabled: Bool {
        get { bool("enabled", true) }
        set { d.set(newValue, forKey: "enabled") }
    }
    var method: InputMethod {
        get { InputMethod(rawValue: d.string(forKey: "method") ?? "") ?? .telex }
        set { d.set(newValue.rawValue, forKey: "method") }
    }
    /// oà, uý instead of òa, úy
    var modernTone: Bool {
        get { bool("modernTone", false) }
        set { d.set(newValue, forKey: "modernTone") }
    }
    /// Spell check + restore keys for non-Vietnamese words.
    var spellCheck: Bool {
        get { bool("spellCheck", true) }
        set { d.set(newValue, forKey: "spellCheck") }
    }
    /// At word end, give back the keys of a Telex word the Vietnamese dictionary does not know.
    var englishRestore: Bool {
        get { bool("englishRestore", true) }
        set { d.set(newValue, forKey: "englishRestore") }
    }
    /// Esc right after a converted word gives back the keys that were typed.
    var escRevert: Bool {
        get { bool("escRevert", true) }
        set { d.set(newValue, forKey: "escRevert") }
    }
    /// Remember on/off per application.
    var smartSwitch: Bool {
        get { bool("smartSwitch", true) }
        set { d.set(newValue, forKey: "smartSwitch") }
    }
    /// Work around inline autocomplete in browser address bars.
    var browserFix: Bool {
        get { bool("browserFix", true) }
        set { d.set(newValue, forKey: "browserFix") }
    }
    /// Skip the address-bar trick when Accessibility says the focus is inside a web page.
    var addressBarOnly: Bool {
        get { bool("addressBarOnly", false) }
        set { d.set(newValue, forKey: "addressBarOnly") }
    }
    /// Fast-typing fallbacks, per app (bundle IDs): pause between the keys ViKey sends.
    var slowApps: Set<String> {
        get { Set(d.stringArray(forKey: "slowApps") ?? []) }
        set { d.set(newValue.sorted(), forKey: "slowApps") }
    }
    /// Send the last character of a change in the real key event.
    var realKeyApps: Set<String> {
        get { Set(d.stringArray(forKey: "realKeyApps") ?? []) }
        set { d.set(newValue.sorted(), forKey: "realKeyApps") }
    }
    var hotkey: Hotkey {
        get { Hotkey(rawValue: d.string(forKey: "hotkey") ?? "") ?? .ctrlShift }
        set { d.set(newValue.rawValue, forKey: "hotkey") }
    }
    /// Abbreviations ("gõ tắt") from a UniKey-format ukmacro.txt.
    var macroEnabled: Bool {
        get { bool("macroEnabled", true) }
        set { d.set(newValue, forKey: "macroEnabled") }
    }
    var macroPath: String? {
        get { d.string(forKey: "macroPath") }
        set { d.set(newValue, forKey: "macroPath") }
    }
    /// Ask GitHub once a day whether a newer release exists.
    var autoUpdateCheck: Bool {
        get { bool("autoUpdateCheck", true) }
        set { d.set(newValue, forKey: "autoUpdateCheck") }
    }
    var appStates: [String: Bool] {
        get { d.dictionary(forKey: "appStates") as? [String: Bool] ?? [:] }
        set { d.set(newValue, forKey: "appStates") }
    }
}
