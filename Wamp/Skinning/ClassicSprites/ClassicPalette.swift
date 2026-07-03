// Wamp/Skinning/ClassicSprites/ClassicPalette.swift
// Colors pixel-sampled from the base-2.91 Winamp skin's BMP sheets.
// Each constant names the sprite region it was sampled from so values can be
// re-verified against skins/base-2.91.wsz.

import AppKit

enum ClassicPalette {
    // MARK: titlebar (TITLEBAR.BMP active strip at (27,0))
    /// Horizontal body ramp: dark at the window edges, lighter at center.
    static let barEdgeLeft = NSColor(hex: 0x101017)
    static let barMid = NSColor(hex: 0x2B2A48)
    static let barEdgeRight = NSColor(hex: 0x1E1D30)
    /// Row 0 (top edge) and rows 12–13 (bottom edge) are darker variants.
    static let barTopEdge = NSColor(hex: 0x0E0E15)
    static let barBottomEdge = NSColor(hex: 0x0D0D12)
    /// Row 1 highlight ridge.
    static let barBevelEdge = NSColor(hex: 0x49494F)
    static let barBevelMid = NSColor(hex: 0x626179)
    static let barCornerDark = NSColor(hex: 0x0C0C10)

    /// The embossed gold "pipe" rows 4–10, top→bottom (active window).
    static let pipeActive: [NSColor] = [
        NSColor(hex: 0x17171C), NSColor(hex: 0xE7C567), NSColor(hex: 0xFFFFFF),
        NSColor(hex: 0x35322E), NSColor(hex: 0x928357), NSColor(hex: 0xE7C567),
        NSColor(hex: 0x1C1C21),
    ]
    /// 1px end caps on the two bright gold rows (indices 1 and 5).
    static let pipeCapTopActive = NSColor(hex: 0x928357)
    static let pipeCapBottomActive = NSColor(hex: 0x605941)

    /// Inactive-window pipe rows (TITLEBAR.BMP strip at (27,15)).
    static let pipeInactive: [NSColor] = [
        NSColor(hex: 0x17171A), NSColor(hex: 0x73653C), NSColor(hex: 0x7D7D7D),
        NSColor(hex: 0x272421), NSColor(hex: 0x4F4835), NSColor(hex: 0x73653C),
        NSColor(hex: 0x1A1A1C),
    ]
    static let pipeCapTopInactive = NSColor(hex: 0x4F4835)
    static let pipeCapBottomInactive = NSColor(hex: 0x35322E)

    static let titleTextActive = NSColor(hex: 0xFFFFFF)
    static let titleTextInactive = NSColor(hex: 0x7D7D7D)

    /// Gold glyph tones shared by the titlebar buttons and menu icon.
    static let goldBright = NSColor(hex: 0xEAB154)
    static let goldMid = NSColor(hex: 0xA78C43)
    static let goldDim = NSColor(hex: 0x8E6F28)
}
