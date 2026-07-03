// Wamp/Skinning/ClassicSprites/ClassicSpriteFactory.swift
// Vector recreations of the base-2.91 skin sprites. Each image is backed by a
// drawing handler, so AppKit rasterizes it at the destination's live backing
// scale — crisp at the app's 1.3× window scale, Double Size, and Retina,
// unlike the 1× bitmaps inside a .wsz.

import AppKit

enum ClassicSprites {
    /// Vector-drawn stand-in for `SpriteCoordinates.resolve(key)`'s bitmap.
    /// Returns nil for keys not yet recreated (caller falls back accordingly).
    static func image(_ key: SpriteKey) -> NSImage? {
        switch key {
        case .mainBackground:
            return ClassicMainFace.background()
        case .titleBarActive:
            return ClassicTitleBar.bar(active: true)
        case .titleBarInactive:
            return ClassicTitleBar.bar(active: false)
        case .titleBarCloseButton(let pressed):
            return ClassicTitleBar.closeButton(pressed: pressed)
        case .titleBarShadeButton(let pressed):
            return ClassicTitleBar.shadeButton(pressed: pressed)
        case .previous, .play, .pause, .stop, .next, .eject:
            return ClassicButtons.transport(key)
        case .shuffleButton, .repeatButton, .eqToggleButton, .plToggleButton, .mono, .stereo:
            return ClassicButtons.toggle(key)
        case .digit(let n):
            return ClassicDigits.digit(n)
        case .seekBackground:
            return ClassicSliders.seekBackground()
        case .seekThumb(let pressed):
            return ClassicSliders.seekThumb(pressed: pressed)
        case .volumeBackground(let position):
            return ClassicSliders.tintedBar(width: 68, position: position)
        case .balanceBackground(let position):
            return ClassicSliders.tintedBar(width: 38, position: position)
        case .volumeThumb(let pressed), .balanceThumb(let pressed):
            return ClassicSliders.volumeThumb(pressed: pressed)
        case .eqBackground:
            return ClassicEqualizer.background()
        case .eqTitleBar(let active):
            return ClassicTitleBar.eqBar(active: active)
        case .eqSliderBackground(let position):
            return ClassicEqualizer.sliderBackground(position: position)
        case .eqSliderThumb(let pressed):
            return ClassicButtons.fromSheet(pressed ? ClassicEQSheets.eqThumbPressed
                                                    : ClassicEQSheets.eqThumb,
                                            colors: ClassicEQSheets.colors)
        case .eqOnButton(let active, let pressed):
            return ClassicButtons.fromSheet(eqSheet(active, pressed,
                                                    ClassicEQSheets.eqOnOff, ClassicEQSheets.eqOnOffPressed,
                                                    ClassicEQSheets.eqOnActive, ClassicEQSheets.eqOnActivePressed),
                                            colors: ClassicEQSheets.colors)
        case .eqAutoButton(let active, let pressed):
            return ClassicButtons.fromSheet(eqSheet(active, pressed,
                                                    ClassicEQSheets.eqAutoOff, ClassicEQSheets.eqAutoOffPressed,
                                                    ClassicEQSheets.eqAutoActive, ClassicEQSheets.eqAutoActivePressed),
                                            colors: ClassicEQSheets.colors)
        case .eqPresetsButton(let pressed):
            return ClassicButtons.fromSheet(pressed ? ClassicEQSheets.eqPresetsPressed
                                                    : ClassicEQSheets.eqPresets,
                                            colors: ClassicEQSheets.colors)
        case .eqGraphBackground:
            return ClassicButtons.fromSheet(ClassicEQSheets.eqGraphBg,
                                            colors: ClassicEQSheets.colors)
        default:
            return nil
        }
    }

    private static func eqSheet(_ active: Bool, _ pressed: Bool,
                                _ off: [String], _ offPressed: [String],
                                _ on: [String], _ onPressed: [String]) -> [String] {
        switch (active, pressed) {
        case (false, false): return off
        case (false, true):  return offPressed
        case (true, false):  return on
        case (true, true):   return onPressed
        }
    }
}

enum ClassicDraw {
    /// A drawing-handler image using Winamp's Y-down coordinates.
    static func image(width: Int, height: Int, _ draw: @escaping (NSRect) -> Void) -> NSImage {
        let img = NSImage(size: NSSize(width: width, height: height), flipped: true) { rect in
            draw(rect)
            return true
        }
        return img
    }

    static func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
        color.setFill()
        NSRect(x: x, y: y, width: w, height: h).fill()
    }

    /// Draws a character-per-pixel map at `origin`. Space = transparent.
    /// Sprite pixels become 1-point rects, which rasterize as crisp squares
    /// at any backing scale.
    static func pixelMap(_ rows: [String], at origin: NSPoint, colors: [Character: NSColor]) {
        for (ry, row) in rows.enumerated() {
            for (rx, ch) in row.enumerated() where ch != " " {
                guard let c = colors[ch] else { continue }
                px(origin.x + CGFloat(rx), origin.y + CGFloat(ry), 1, 1, c)
            }
        }
    }

    /// Horizontal 3-stop ramp (edge → mid → edge) across a row band —
    /// the base-2.91 titlebar/body sheets shade horizontally, not vertically.
    static func hRamp(y: CGFloat, height: CGFloat, width: CGFloat,
                      left: NSColor, mid: NSColor, right: NSColor) {
        NSGradient(colors: [left, mid, right])?
            .draw(in: NSRect(x: 0, y: y, width: width, height: height), angle: 0)
    }

    /// The shared window frame of the main and EQ faces: dark outline, light
    /// bevel row/columns (left col 1, right col width-4).
    static func windowFrame(width: Int, height: Int) {
        let w = CGFloat(width), h = CGFloat(height)
        hRamp(y: 0, height: 1, width: w,
              left: NSColor(hex: 0x0C0C10), mid: NSColor(hex: 0x1E1D30),
              right: NSColor(hex: 0x161622))
        hRamp(y: 1, height: 1, width: w,
              left: NSColor(hex: 0x4A4950), mid: NSColor(hex: 0x626179),
              right: NSColor(hex: 0x565565))
        hRamp(y: h - 1, height: 1, width: w,
              left: NSColor(hex: 0x101017), mid: NSColor(hex: 0x1E1D30),
              right: NSColor(hex: 0x161420))
        px(0, 0, 1, h, NSColor(hex: 0x0C0C10))
        px(1, 1, 1, h - 2, NSColor(hex: 0x4F4F5A))
        px(w - 1, 0, 1, h, NSColor(hex: 0x14141D))
        px(w - 4, 2, 1, h - 4, NSColor(hex: 0x52525F))
    }
}
