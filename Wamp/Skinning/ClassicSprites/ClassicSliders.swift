// Wamp/Skinning/ClassicSprites/ClassicSliders.swift
// Vector recreation of POSBAR.BMP, VOLUME.BMP, and BALANCE.BMP. The 28
// pre-rendered volume/balance frames collapse into one parameterized draw:
// a position-tinted bar (base hue from the 28-stop sweep sampled off
// VOLUME.BMP row 6) with fixed shading rows and end caps.

import AppKit

enum ClassicSliders {
    /// Base hue of each VOLUME.BMP frame (green → yellow → red).
    static let sweep: [UInt32] = [
        0x1A830C, 0x2EA712, 0x4CB01F, 0x5BD725, 0x6BD725, 0x72E125, 0x83E025,
        0x96E02B, 0x96E02B, 0xB1E02C, 0xBBD625, 0xBBD625, 0xBBD625, 0xBBD625,
        0xD9D525, 0xD8C025, 0xD8C025, 0xD8C025, 0xD8A420, 0xD7801F, 0xD7801F,
        0xCE6819, 0xB8640F, 0xD65D18, 0xD64618, 0xD63618, 0xD61512, 0xD60012,
    ]

    // MARK: - Seek (posbar)

    static func seekBackground() -> NSImage {
        ClassicDraw.image(width: 248, height: 10) { _ in
            // Recessed groove: 2 dark top rows, interior, light bottom bevel —
            // each with the face's horizontal luminance ramp.
            ClassicDraw.hRamp(y: 0, height: 2, width: 248,
                              left: NSColor(hex: 0x0D0D13), mid: NSColor(hex: 0x1B1A2A),
                              right: NSColor(hex: 0x222136))
            ClassicDraw.hRamp(y: 2, height: 7, width: 248,
                              left: NSColor(hex: 0x101016), mid: NSColor(hex: 0x232137),
                              right: NSColor(hex: 0x2A2846))
            ClassicDraw.hRamp(y: 9, height: 1, width: 248,
                              left: NSColor(hex: 0x4E4F5A), mid: NSColor(hex: 0x555463),
                              right: NSColor(hex: 0x5A596B))
        }
    }

    /// Gold bar thumb: horizontal highlight/shadow bands drawn as continuous
    /// rows (crisp at fractional scales), dark frame.
    static func seekThumb(pressed: Bool) -> NSImage {
        ClassicDraw.image(width: 29, height: 10) { _ in
            let rows: [UInt32] = pressed
                ? [0xA0874C, 0xB69F62, 0xCFBA81, 0xB69F62, 0x7C632C, 0x8F743B, 0xB69F62, 0x8F743B, 0x644B19, 0x180B00]
                : [0xD2C18D, 0x6F5724, 0xF1E6BB, 0xF2F2F2, 0x61491A, 0x9F874F, 0xF1E6BB, 0x9F874F, 0x7A632C, 0x0A0202]
            for (i, hex) in rows.enumerated() {
                ClassicDraw.px(1, CGFloat(i), 27, 1, NSColor(hex: hex))
            }
            ClassicDraw.px(0, 0, 1, 10, NSColor(hex: 0x525260))
            ClassicDraw.px(28, 0, 1, 10, NSColor(hex: pressed ? 0x180B00 : 0x0A0202))
        }
    }

    // MARK: - Volume / balance tinted bars

    /// One VOLUME.BMP/BALANCE.BMP frame: body, dark top edge, four shaded
    /// hue rows with darker end caps, lavender shadow row.
    static func tintedBar(width: Int, position: Int) -> NSImage {
        let hue = sweep[max(0, min(27, position))]
        return ClassicDraw.image(width: width, height: 13) { _ in
            let w = CGFloat(width)
            let barEnd = w - 4
            ClassicDraw.hRamp(y: 0, height: 13, width: w,
                              left: NSColor(hex: 0x26253E), mid: NSColor(hex: 0x292844),
                              right: NSColor(hex: 0x2B2A48))
            ClassicDraw.px(0, 3, barEnd, 1, NSColor(hex: 0x12121B))
            let rows: [(CGFloat, CGFloat)] = [(4, 0.66), (5, 0.85), (6, 1.0), (7, 1.08)]
            for (y, factor) in rows {
                let c = shade(hue, factor)
                ClassicDraw.px(1, y, barEnd - 1, 1, c)
                ClassicDraw.px(1, y, 1, 1, shade(hue, factor * 0.55))
                ClassicDraw.px(2, y, 1, 1, shade(hue, factor * 0.85))
                ClassicDraw.px(barEnd - 2, y, 1, 1, shade(hue, factor * 0.85))
                ClassicDraw.px(barEnd - 1, y, 1, 1, shade(hue, factor * 0.55))
            }
            ClassicDraw.px(2, 8, barEnd - 3, 1, NSColor(hex: 0x6B6A80))
            ClassicDraw.px(barEnd - 1, 8, 2, 1, NSColor(hex: 0x7B7B90))
        }
    }

    /// Silver grip thumb (volume/balance). Pressed inverts to the dark face
    /// with light grips, like VOLUME.BMP's pressed variant.
    static func volumeThumb(pressed: Bool) -> NSImage {
        silverThumb(width: 14, height: 11, pressed: pressed, gripCount: 3)
    }

    /// EQ band thumb — same family, square with a center grip.
    static func eqThumb(pressed: Bool) -> NSImage {
        silverThumb(width: 11, height: 11, pressed: pressed, gripCount: 1)
    }

    private static func silverThumb(width: Int, height: Int, pressed: Bool,
                                    gripCount: Int) -> NSImage {
        ClassicDraw.image(width: width, height: height) { rect in
            let w = rect.width, h = rect.height
            let face = NSColor(hex: pressed ? 0x10151B : 0x9DAEB7)
            let grip = NSColor(hex: pressed ? 0xFFFFFF : 0x0B0D11)
            ClassicDraw.px(0, 0, w, h, NSColor(hex: 0x0B0D11))
            ClassicDraw.px(1, 1, w - 2, h - 2, face)
            ClassicDraw.px(1, 1, w - 2, 1, NSColor(hex: 0xD2E1E5))
            ClassicDraw.px(1, 1, 1, h - 2, NSColor(hex: 0xD2E1E5))
            if !pressed {
                ClassicDraw.px(1, h - 3, w - 2, 1, NSColor(hex: 0x687082))
                ClassicDraw.px(1, h - 2, w - 2, 1, NSColor(hex: 0x3A4858))
                ClassicDraw.px(w - 2, 1, 1, h - 2, NSColor(hex: 0x687082))
            }
            let mid = (w / 2).rounded()
            let spread: CGFloat = 2
            for g in 0..<gripCount {
                let gx = mid + (CGFloat(g) - CGFloat(gripCount - 1) / 2) * spread - 0.5
                ClassicDraw.px(gx, 3, 1, h - 6, grip)
            }
        }
    }

    private static func shade(_ hex: UInt32, _ factor: CGFloat) -> NSColor {
        let r = min(1, CGFloat((hex >> 16) & 0xFF) / 255 * factor)
        let g = min(1, CGFloat((hex >> 8) & 0xFF) / 255 * factor)
        let b = min(1, CGFloat(hex & 0xFF) / 255 * factor)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
