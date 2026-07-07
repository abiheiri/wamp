import Cocoa
import Combine

enum WinampButtonStyle {
    case transport
    case toggle
    case action
}

class WinampButton: NSView {
    var title: String = "" { didSet { needsDisplay = true } }
    var isActive = false { didSet { needsDisplay = true } }
    var isPressed = false { didSet { needsDisplay = true } }
    var style: WinampButtonStyle = .transport
    var onClick: (() -> Void)?
    var drawIcon: ((NSRect, Bool) -> Void)? // custom icon drawer (rect, isActive)

    /// Closure that maps (active, pressed) → SpriteKey. Set by parent views.
    /// When non-nil and the sprite resolves, the button renders the sprite
    /// instead of the programmatic path.
    var spriteKeyProvider: ((Bool, Bool) -> SpriteKey)?

    private var skinObserver: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError() }

    convenience init(title: String, style: WinampButtonStyle = .action) {
        self.init(frame: .zero)
        self.title = title
        self.style = style
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Sprite path: if a sprite key provider is set and the sprite resolves,
        // blit it as the entire button face and skip the programmatic path.
        if WinampTheme.skinIsActive,
           let provide = spriteKeyProvider,
           let sprite = WinampTheme.sprite(provide(isActive, isPressed)) {
            let ctx = NSGraphicsContext.current
            ctx?.imageInterpolation = .none
            ctx?.shouldAntialias = false
            sprite.draw(in: backingAlignedRect(bounds, options: .alignAllEdgesNearest))
            return
        }

        let b = bounds

        // Classic silver face (CBUTTONS family): flat fill, light bevel on
        // the visual top/left, stepped shadow on bottom/right. AppKit y-up:
        // visual top = maxY.
        NSColor(hex: isPressed ? 0xA3B5C0 : 0xB0C3CD).setFill()
        b.fill()
        let light = NSColor(hex: isPressed ? 0x3A4858 : 0xEBFFFF)
        let shadowMid = NSColor(hex: isPressed ? 0xEBFFFF : 0x718194)
        let shadowDark = NSColor(hex: isPressed ? 0x9DA6BA : 0x3A4858)
        NSColor(hex: 0x9DA6BA).setFill()
        NSRect(x: 0, y: b.height - 1, width: b.width, height: 1).fill()
        NSRect(x: 0, y: 0, width: 1, height: b.height).fill()
        light.setFill()
        NSRect(x: 1, y: b.height - 2, width: b.width - 2, height: 1).fill()
        NSRect(x: 1, y: 1, width: 1, height: b.height - 2).fill()
        shadowMid.setFill()
        NSRect(x: 1, y: 1, width: b.width - 2, height: 1).fill()
        NSRect(x: b.width - 2, y: 1, width: 1, height: b.height - 2).fill()
        shadowDark.setFill()
        NSRect(x: 0, y: 0, width: b.width, height: 1).fill()
        NSRect(x: b.width - 1, y: 0, width: 1, height: b.height).fill()

        // Content
        let pressOffset: CGFloat = isPressed ? 1 : 0
        if let drawIcon = drawIcon {
            drawIcon(b.insetBy(dx: 4, dy: 3).offsetBy(dx: pressOffset, dy: -pressOffset), isActive)
        } else if !title.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: WinampTheme.buttonFont,
                .foregroundColor: NSColor(hex: 0x2E374C)
            ]
            let size = title.size(withAttributes: attrs)
            let point = NSPoint(
                x: (b.width - size.width) / 2 + pressOffset,
                y: (b.height - size.height) / 2 - pressOffset
            )
            title.draw(at: point, withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }
}
