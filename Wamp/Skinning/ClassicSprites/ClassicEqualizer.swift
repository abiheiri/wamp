// Wamp/Skinning/ClassicSprites/ClassicEqualizer.swift
// Vector recreation of EQMAIN.BMP: window background (structural body +
// extracted label strips), the 28-stop slider line frames, and the EQ
// response-graph palette sampled from the sheet.

import AppKit

enum ClassicEqualizer {
    /// Line color of each slider frame — both sheet rows, green → red.
    static let lineSweep: [UInt32] = [
        0x258C12, 0x258C12, 0x4BA521, 0x62C728, 0x62C728, 0x7AE125, 0x7AE125,
        0x96E02B, 0x96E02B, 0xB8D727, 0xB8D727, 0xB8D727, 0xB8D727, 0xB8D727,
        0xD8C525, 0xD8C525, 0xD8C525, 0xD8C525, 0xD8A420, 0xD7801F, 0xD7801F,
        0xD26219, 0xB8640F, 0xD26219, 0xD63E18, 0xD63E18, 0xC60B16, 0xC60B16,
    ]

    /// EQ response curve palette (eqmain.bmp x=115, y=294..312; top = +12dB).
    static let graphLineColors: [NSColor] = [
        0xD2221B, 0xEE5220, 0xEE7B20, 0xE09227, 0xE09227, 0xE09227, 0xE0B128,
        0xEFDB30, 0xEFDB30, 0xEFDB30, 0xD2EB34, 0xD2EB34, 0xA4E137, 0xA4E137,
        0x89E22F, 0x71CD34, 0x59B02B, 0x299915, 0x299915,
    ].map { NSColor(hex: $0) }

    static let preampLineColor = NSColor(hex: 0xB9CADD)

    static func background() -> NSImage {
        ClassicDraw.image(width: 275, height: 116) { _ in
            ClassicDraw.hRamp(y: 0, height: 116, width: 275,
                              left: NSColor(hex: 0x12121B),
                              mid: NSColor(hex: 0x2A2945),
                              right: NSColor(hex: 0x1D1C2E))
            ClassicDraw.windowFrame(width: 275, height: 116)
            // Baked details extracted 1:1 from the sheet: the tick ladder,
            // the three gold dB labels with their dashed guide rows, and the
            // band-frequency label row.
            ClassicDraw.pixelMap(ClassicEQSheets.eqLadder, at: NSPoint(x: 84, y: 16),
                                 colors: ClassicEQSheets.colors)
            ClassicDraw.pixelMap(ClassicEQSheets.eqDbRowTop, at: NSPoint(x: 14, y: 35),
                                 colors: ClassicEQSheets.colors)
            ClassicDraw.pixelMap(ClassicEQSheets.eqDbRowMid, at: NSPoint(x: 14, y: 64),
                                 colors: ClassicEQSheets.colors)
            ClassicDraw.pixelMap(ClassicEQSheets.eqDbRowBottom, at: NSPoint(x: 14, y: 94),
                                 colors: ClassicEQSheets.colors)
            ClassicDraw.pixelMap(ClassicEQSheets.eqLabelStrip, at: NSPoint(x: 0, y: 102),
                                 colors: ClassicEQSheets.colors)
        }
    }

    /// One 14×63 slider frame: dark left edge, 4px colored line with fade-in
    /// ends, grey companion column.
    static func sliderBackground(position: Int) -> NSImage {
        let hue = lineSweep[max(0, min(27, position))]
        return ClassicDraw.image(width: 14, height: 63) { _ in
            ClassicDraw.px(0, 0, 14, 63, NSColor(hex: 0x292843))
            ClassicDraw.px(3, 0, 6, 1, NSColor(hex: 0x191827))
            ClassicDraw.px(3, 1, 1, 61, NSColor(hex: 0x0F0F16))
            let fades: [(CGFloat, CGFloat)] = [(1, 0.45), (2, 0.72), (3, 0.88), (60, 0.8)]
            ClassicDraw.px(4, 1, 4, 60, shade(hue, 1.0))
            for (y, f) in fades {
                ClassicDraw.px(4, y, 4, 1, shade(hue, f))
            }
            ClassicDraw.px(8, 3, 1, 58, NSColor(hex: 0x7A7B8B))
            ClassicDraw.px(8, 61, 1, 1, NSColor(hex: 0x706F83))
        }
    }

    private static func shade(_ hex: UInt32, _ factor: CGFloat) -> NSColor {
        NSColor(srgbRed: min(1, CGFloat((hex >> 16) & 0xFF) / 255 * factor),
                green: min(1, CGFloat((hex >> 8) & 0xFF) / 255 * factor),
                blue: min(1, CGFloat(hex & 0xFF) / 255 * factor), alpha: 1)
    }
}
