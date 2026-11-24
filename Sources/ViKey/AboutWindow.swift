import AppKit
import CoreText

/// "Giới thiệu ViKey": what the app is, plus the Sunny Side Projects endorsement.
/// Follows the SSP brand book: cream/pan surface, ink text, yolk-ink links, the project name in
/// Bricolage Grotesque, the status badge next to it, and the "[Project] · a Sunny Side Project" line.
/// Assets (logo, font) are copied into Contents/Resources by build.sh; under `swift run` they are
/// missing and the window falls back to the system font and no logo.
final class AboutWindow: NSWindowController {
    private static var shared: AboutWindow?

    static let siteURL = URL(string: "https://sunnysideprojects.dev")!
    static let githubURL = URL(string: "https://github.com/sunnysideprojects")!

    static func show() {
        let controller = shared ?? AboutWindow()
        shared = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.center()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 100),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Giới thiệu ViKey"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = Brand.surface
        super.init(window: window)
        let content = Self.makeContent()
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(content.fittingSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Layout

    private static func makeContent() -> NSView {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String

        // ViKey
        let name = label("ViKey", font: Brand.display(34), color: Brand.ink)
        let titleRow = NSStackView(views: [name, StatusBadge(text: "Cooking")])
        titleRow.alignment = .centerY
        titleRow.spacing = 12

        let versionLabel = label(
            "Phiên bản \(version)" + (build.map { " (\($0))" } ?? ""),
            font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: Brand.inkMuted)

        let about = paragraph(
            "Bộ gõ tiếng Việt kiểu UniKey cho macOS. Tôi làm ViKey vì bộ gõ có sẵn của macOS cứ gạch chân "
                + "chữ đang gõ. ViKey gõ thẳng vào ô chữ, không gạch chân, không cửa sổ gợi ý.",
            size: 13, color: Brand.ink)
        let features = paragraph(
            "Telex và VNI. Gõ tắt dùng chung file ukmacro.txt với UniKey. "
                + "Không tài khoản, không gửi gì ra ngoài máy.",
            size: 12, color: Brand.inkMuted)

        let vikey = NSStackView(views: [titleRow, versionLabel, about, features])
        vikey.orientation = .vertical
        vikey.alignment = .leading
        vikey.spacing = 6
        vikey.setCustomSpacing(14, after: versionLabel)

        // Sunny Side Projects
        let logo = NSImageView()
        if let url = Bundle.main.url(forResource: "ssp-app-icon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            logo.image = image
        }
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 56),
            logo.heightAnchor.constraint(equalToConstant: 56),
        ])
        logo.isHidden = logo.image == nil

        let endorse = NSStackView(views: [
            label("ViKey · a ", font: .systemFont(ofSize: 13, weight: .semibold), color: Brand.ink),
            LinkButton("Sunny Side Project", url: siteURL, size: 13, weight: .semibold),
        ])
        endorse.spacing = 0
        endorse.alignment = .firstBaseline

        let tagline = label(
            "Small useful things, served sunny side up.",
            font: NSFontManager.shared.convert(.systemFont(ofSize: 12), toHaveTrait: .italicFontMask),
            color: Brand.inkMuted)

        let links = NSStackView(views: [
            LinkButton("sunnysideprojects.dev", url: siteURL, size: 12),
            label("·", font: .systemFont(ofSize: 12), color: Brand.inkMuted),
            LinkButton("GitHub", url: githubURL, size: 12),
        ])
        links.spacing = 6
        links.alignment = .firstBaseline

        let sspText = NSStackView(views: [endorse, tagline, links])
        sspText.orientation = .vertical
        sspText.alignment = .leading
        sspText.spacing = 3
        sspText.setCustomSpacing(8, after: tagline)

        let ssp = NSStackView(views: [logo, sspText])
        ssp.alignment = .centerY
        ssp.spacing = 14

        let copyright = label(
            "© 2026 Nhat (@nhatnx)", font: .systemFont(ofSize: 11), color: Brand.inkMuted)

        let line = Hairline()
        let root = NSStackView(views: [vikey, line, ssp, copyright])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 40, left: 28, bottom: 22, right: 28)
        root.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 420),
            line.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56),
            about.widthAnchor.constraint(equalTo: line.widthAnchor),
            features.widthAnchor.constraint(equalTo: line.widthAnchor),
        ])
        return container
    }

    private static func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font
        l.textColor = color
        return l
    }

    private static func paragraph(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: size)
        l.textColor = color
        l.isSelectable = false
        return l
    }
}

// MARK: - Brand tokens (SSP tokens.json, light / dark)

enum Brand {
    static let surface = dynamic(0xFFF8EC, 0x1C1814)
    static let ink = dynamic(0x231C15, 0xFBF3E6)
    static let inkMuted = dynamic(0x6B5D4F, 0xB9AC9C)
    static let line = dynamic(0xEADCC4, 0x3A322A)
    static let yolkInk = dynamic(0x8A5300, 0xFFC94D)
    static let sunrise = dynamic(0xFB8500, 0xFF9A3C)
    static let sunriseSoft = dynamic(0xFFE1C4, 0x4D2A0E)
    static let sunriseInk = dynamic(0x9C4300, 0xFFB27A)

    private static func dynamic(_ light: Int, _ dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return hex(isDark ? dark : light)
        }
    }

    private static func hex(_ v: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// Bricolage Grotesque (variable) at the given weight, from the app bundle.
    static func display(_ size: CGFloat, weight: CGFloat = 800) -> NSFont {
        guard let url = Bundle.main.url(forResource: "BricolageGrotesque-Variable", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let base = descriptors.first
        else { return .systemFont(ofSize: size, weight: .heavy) }
        let wght = 0x7767_6874 as CFNumber  // 'wght' axis
        let descriptor = CTFontDescriptorCreateCopyWithVariation(base, wght, weight)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }
}

// MARK: - Small views

/// View whose layer colours follow light/dark changes.
private class ThemedView: NSView {
    override var wantsUpdateLayer: Bool { true }
    var fill: NSColor = .clear { didSet { needsDisplay = true } }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fill.cgColor
        }
    }
}

private final class Hairline: ThemedView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        fill = Brand.line
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Project status pill: dot + word (colour never carries the status alone).
private final class StatusBadge: ThemedView {
    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        fill = Brand.sunriseSoft
        layer?.cornerRadius = 10

        let dot = ThemedView()
        dot.wantsLayer = true
        dot.fill = Brand.sunrise
        dot.layer?.cornerRadius = 3.5
        dot.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = Brand.sunriseInk

        let row = NSStackView(views: [dot, label])
        row.spacing = 5
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: 9, bottom: 0, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 20),
        ])
        // No intrinsic width: shrink to the dot + word instead of filling the row.
        let shrink = widthAnchor.constraint(equalToConstant: 0)
        shrink.priority = .defaultLow
        shrink.isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Borderless text button in yolk-ink that opens a URL.
private final class LinkButton: NSButton {
    private let url: URL

    init(_ title: String, url: URL, size: CGFloat, weight: NSFont.Weight = .regular) {
        self.url = url
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryChange)
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: Brand.yolkInk,
        ])
        toolTip = url.absoluteString
        target = self
        action = #selector(open)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func open() { NSWorkspace.shared.open(url) }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
