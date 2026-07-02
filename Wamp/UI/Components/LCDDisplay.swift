import Cocoa
import Combine

class LCDDisplay: NSView {
    var text: String = "" {
        didSet {
            scrollOffset = 0
            cachedTextWidth = textSize().width + 30
            marqueeStrip = nil
            updateScrollTimer()
            needsDisplay = true
        }
    }
    var isScrolling = true { didSet { updateScrollTimer() } }

    private var scrollOffset: CGFloat = 0
    private var cachedTextWidth: CGFloat = 0
    /// The doubled title (text + separator + text) pre-rendered once. Per-glyph
    /// sprite rendering is far too slow to repeat 30×/sec — the marquee frame
    /// just blits this image at the current scroll offset.
    private var marqueeStrip: NSImage?
    private var scrollTimer: Timer?
    private let scrollSpeed: CGFloat = 0.5
    private var skinObserver: AnyCancellable?
    private var overlayText: String?
    private var overlayClearTimer: Timer?

    func showOverlay(_ text: String, duration: TimeInterval = 1.0) {
        overlayText = text
        needsDisplay = true
        overlayClearTimer?.invalidate()
        overlayClearTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.overlayText = nil
            self?.needsDisplay = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.marqueeStrip = nil
                self?.needsDisplay = true
            }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The marquee timer exists only while a too-wide title is actually
    /// scrolling. Titles that fit are static and need no timer at all, and the
    /// width is measured once per title change instead of on every tick.
    /// Scrolling keeps going while paused, matching classic Winamp.
    private func updateScrollTimer() {
        let needsMarquee = isScrolling && !text.isEmpty && cachedTextWidth > bounds.width
        guard needsMarquee else {
            scrollTimer?.invalidate()
            scrollTimer = nil
            return
        }
        guard scrollTimer == nil else { return }
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.scrollOffset += self.scrollSpeed
            if self.scrollOffset > self.cachedTextWidth {
                self.scrollOffset = -self.bounds.width
            }
            self.needsDisplay = true
        }
    }

    override func layout() {
        super.layout()
        // Bounds changes (initial layout, Double Size) change whether the
        // current title overflows, and invalidate the strip's baked-in
        // vertical centering.
        if let strip = marqueeStrip, strip.size.height != bounds.height {
            marqueeStrip = nil
        }
        updateScrollTimer()
    }

    /// Builds the pre-rendered marquee strip: the doubled title with vertical
    /// centering baked in, sized to the current bounds height. The drawing
    /// handler runs once per backing scale and AppKit caches the raster.
    private func makeMarqueeStrip() -> NSImage? {
        let height = bounds.height
        guard height > 0, !text.isEmpty else { return nil }

        if WinampTheme.skinIsActive {
            guard let sheet = WinampTheme.provider.textSheet else { return nil }
            let combined = text + "   *   " + text
            let width = TextSpriteRenderer.width(of: combined)
            let y = (height - TextSpriteRenderer.glyphHeight) / 2
            return NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
                TextSpriteRenderer.draw(combined, at: NSPoint(x: 0, y: y), sheet: sheet)
                return true
            }
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: WinampTheme.trackTitleFont,
                .foregroundColor: WinampTheme.greenBright
            ]
            let combined = text + "   ★   " + text
            let size = combined.size(withAttributes: attrs)
            let y = (height - size.height) / 2
            return NSImage(size: NSSize(width: max(1, size.width), height: height), flipped: false) { _ in
                combined.draw(at: NSPoint(x: 0, y: y), withAttributes: attrs)
                return true
            }
        }
    }

    private func textSize() -> NSSize {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: WinampTheme.trackTitleFont,
            .foregroundColor: WinampTheme.greenBright
        ]
        return text.size(withAttributes: attrs)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if WinampTheme.skinIsActive {
            drawSkinned()
        } else {
            drawBuiltIn()
        }
    }

    private func drawSkinned() {
        guard let textSheet = WinampTheme.provider.textSheet else { return }
        if let overlay = overlayText {
            let y = (bounds.height - TextSpriteRenderer.glyphHeight) / 2
            TextSpriteRenderer.draw(overlay, at: NSPoint(x: 2, y: y), sheet: textSheet)
            return
        }
        guard !text.isEmpty else { return }
        let textWidth = TextSpriteRenderer.width(of: text)
        let y = (bounds.height - TextSpriteRenderer.glyphHeight) / 2

        if textWidth <= bounds.width || !isScrolling {
            TextSpriteRenderer.draw(text, at: NSPoint(x: 2, y: y), sheet: textSheet)
        } else {
            if marqueeStrip == nil { marqueeStrip = makeMarqueeStrip() }
            let ctx = NSGraphicsContext.current
            let prevInterpolation = ctx?.imageInterpolation
            ctx?.imageInterpolation = .none
            marqueeStrip?.draw(at: NSPoint(x: -scrollOffset, y: 0), from: .zero,
                               operation: .sourceOver, fraction: 1.0)
            if let prev = prevInterpolation { ctx?.imageInterpolation = prev }
        }
    }

    private func drawBuiltIn() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: WinampTheme.trackTitleFont,
            .foregroundColor: WinampTheme.greenBright
        ]

        if let overlay = overlayText {
            let size = overlay.size(withAttributes: attrs)
            let y = (bounds.height - size.height) / 2
            overlay.draw(at: NSPoint(x: 2, y: y), withAttributes: attrs)
            return
        }

        let size = text.size(withAttributes: attrs)
        let y = (bounds.height - size.height) / 2

        if size.width <= bounds.width || !isScrolling {
            text.draw(at: NSPoint(x: 2, y: y), withAttributes: attrs)
        } else {
            if marqueeStrip == nil { marqueeStrip = makeMarqueeStrip() }
            marqueeStrip?.draw(at: NSPoint(x: -scrollOffset, y: 0), from: .zero,
                               operation: .sourceOver, fraction: 1.0)
        }
    }

    deinit {
        scrollTimer?.invalidate()
        overlayClearTimer?.invalidate()
    }
}
