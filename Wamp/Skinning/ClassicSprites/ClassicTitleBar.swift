// Wamp/Skinning/ClassicSprites/ClassicTitleBar.swift
// Vector recreation of TITLEBAR.BMP: the 275×14 main-window title bar with
// its embossed gold pipes, plus the 9×9 close/shade buttons. Geometry and
// colors come from RLE dumps of the base-2.91 sheet (see ClassicPalette).

import AppKit

enum ClassicTitleBar {
    private static let width = 275
    private static let height = 14
    /// Right edge of the pipe area — the three window buttons start at x=242.
    private static let pipesEnd: CGFloat = 240
    private static let pipesStart: CGFloat = 17

    static func bar(active: Bool) -> NSImage {
        bar(active: active, title: "WAMP", menuGlyph: true, minimizeAndShade: true)
    }

    /// The EQ window's title strip (lives in eqmain.bmp in real skins):
    /// same chrome, its own title, close button only.
    static func eqBar(active: Bool) -> NSImage {
        bar(active: active, title: "EQUALIZER", menuGlyph: false, minimizeAndShade: false)
    }

    private static func bar(active: Bool, title: String,
                            menuGlyph: Bool, minimizeAndShade: Bool) -> NSImage {
        ClassicDraw.image(width: width, height: height) { _ in
            drawBody()
            if menuGlyph { drawMenuGlyph(active: active) }

            // Title, centered; pipes fill the space to either side of it.
            let attrs: [NSAttributedString.Key: Any] = [
                .font: WinampTheme.titleBarFont,
                .foregroundColor: active ? ClassicPalette.titleTextActive
                                         : ClassicPalette.titleTextInactive,
                .kern: 1.2,
            ]
            let size = title.size(withAttributes: attrs)
            let tx = (CGFloat(width) - size.width) / 2
            title.draw(at: NSPoint(x: tx, y: (CGFloat(height) - size.height) / 2),
                       withAttributes: attrs)

            // With only a close button on the right, the pipe runs up to it.
            let pipesLeft = menuGlyph ? pipesStart : 8
            let pipesRight = minimizeAndShade ? pipesEnd : 260
            drawPipe(from: pipesLeft, to: (tx - 4).rounded(.down), active: active)
            drawPipe(from: (tx + size.width + 4).rounded(.up), to: pipesRight, active: active)

            // Baked window buttons at the hit rects TitleBarView uses
            // (width-33 / width-22 / width-11).
            if minimizeAndShade {
                ClassicDraw.pixelMap(minimizeGlyph, at: NSPoint(x: 242, y: 3), colors: glyphColors)
                ClassicDraw.pixelMap(shadeUnpressed, at: NSPoint(x: 253, y: 3), colors: glyphColors)
            }
            ClassicDraw.pixelMap(closeUnpressed, at: NSPoint(x: 264, y: 3), colors: glyphColors)
        }
    }

    static func closeButton(pressed: Bool) -> NSImage {
        button(pressed ? closePressed : closeUnpressed)
    }

    /// Draws the gold close glyph directly (used by the playlist top-right
    /// corner, which bakes its own ×).
    static func drawCloseGlyph(at origin: NSPoint) {
        ClassicDraw.pixelMap(closeUnpressed, at: origin, colors: glyphColors)
    }

    static func shadeButton(pressed: Bool) -> NSImage {
        button(pressed ? shadePressed : shadeUnpressed)
    }

    private static func button(_ map: [String]) -> NSImage {
        ClassicDraw.image(width: 9, height: 9) { _ in
            ClassicDraw.px(0, 0, 9, 9, NSColor(hex: 0x24233A))
            ClassicDraw.pixelMap(map, at: .zero, colors: glyphColors)
        }
    }

    // MARK: - Bar chrome

    private static func drawBody() {
        let w = CGFloat(width)
        // Body: horizontal luminance ramp, dark at edges → lighter center.
        ClassicDraw.hRamp(y: 0, height: CGFloat(height), width: w,
                          left: ClassicPalette.barEdgeLeft,
                          mid: ClassicPalette.barMid,
                          right: ClassicPalette.barEdgeRight)
        // Top edge row, highlight ridge under it, two dark bottom rows.
        ClassicDraw.hRamp(y: 0, height: 1, width: w,
                          left: ClassicPalette.barCornerDark,
                          mid: NSColor(hex: 0x1E1D30), right: NSColor(hex: 0x161622))
        ClassicDraw.hRamp(y: 1, height: 1, width: w,
                          left: ClassicPalette.barBevelEdge,
                          mid: ClassicPalette.barBevelMid, right: NSColor(hex: 0x575667))
        ClassicDraw.hRamp(y: 12, height: 2, width: w,
                          left: ClassicPalette.barBottomEdge,
                          mid: NSColor(hex: 0x1E1D30), right: NSColor(hex: 0x161520))
        ClassicDraw.px(0, 0, 1, CGFloat(height), ClassicPalette.barCornerDark)
        ClassicDraw.px(w - 1, 0, 1, CGFloat(height), NSColor(hex: 0x161420))
    }

    private static func drawPipe(from x0: CGFloat, to x1: CGFloat, active: Bool) {
        guard x1 - x0 >= 4 else { return }
        let rows = active ? ClassicPalette.pipeActive : ClassicPalette.pipeInactive
        for (i, color) in rows.enumerated() {
            ClassicDraw.px(x0, 4 + CGFloat(i), x1 - x0, 1, color)
        }
        // The two bright gold rows end in darker 1px caps.
        let capTop = active ? ClassicPalette.pipeCapTopActive : ClassicPalette.pipeCapTopInactive
        let capBottom = active ? ClassicPalette.pipeCapBottomActive : ClassicPalette.pipeCapBottomInactive
        for x in [x0, x1 - 1] {
            ClassicDraw.px(x, 5, 1, 1, capTop)
            ClassicDraw.px(x, 9, 1, 1, capBottom)
        }
    }

    /// The little gold emblem at the bar's left edge (main menu hit zone).
    private static func drawMenuGlyph(active: Bool) {
        let map = [
            "  E      ",
            " EdE     ",
            "EddE     ",
            "EhhEEhhhE",
            "    EddE ",
            "    EdEE ",
            "     E   ",
        ]
        var colors = glyphColors
        colors["E"] = active ? ClassicPalette.goldBright : ClassicPalette.goldDim
        ClassicDraw.pixelMap(map, at: NSPoint(x: 6, y: 4), colors: colors)
    }

    // MARK: - Glyph pixel maps (from TITLEBAR.BMP RLE dumps)

    private static let glyphColors: [Character: NSColor] = [
        "d": NSColor(hex: 0x272421), "S": NSColor(hex: 0x554728),
        "G": NSColor(hex: 0x584B34), "g": NSColor(hex: 0x928357),
        "o": NSColor(hex: 0x7E5B3A), "W": NSColor(hex: 0xFFFFFF),
        "b": NSColor(hex: 0xB5A34F), "a": NSColor(hex: 0xA47450),
        "t": NSColor(hex: 0x9AACA2), "c": NSColor(hex: 0xC4DBC3),
        "n": NSColor(hex: 0x403A2E), "s": NSColor(hex: 0x35322E),
        "e": NSColor(hex: 0x618188), "f": NSColor(hex: 0x6F867A),
        "m": NSColor(hex: 0x8A7F62), "M": NSColor(hex: 0xB1AC6B),
        "h": NSColor(hex: 0x88754B), "E": ClassicPalette.goldBright,
    ]

    private static let closeUnpressed = [
        "         ",
        " GSdddSG ",
        " SaGSGgS ",
        " dGgogGd ",
        " dSoWoSd ",
        " dGgobGd ",
        " SgGSGbS ",
        " GSdddSG ",
        "         ",
    ]

    private static let closePressed = [
        "ggggggggg",
        "gGSdddSGg",
        "gSdGSGdSg",
        "gdGdodGdg",
        "gdSoWoSdg",
        "gdGdodGdg",
        "gSdGSGdSg",
        "gGSdddSGg",
        "ggggggggg",
    ]

    private static let shadeUnpressed = [
        "         ",
        "  ttttt  ",
        " tccccct ",
        " GGGGGGG ",
        " nGGGGGn ",
        " nnGGGnn ",
        " snnnnn  ",
        "  sssss  ",
        "         ",
    ]

    private static let shadePressed = [
        "         ",
        "  sssss  ",
        " snettes ",
        " nnttttn ",
        " ncttttn ",
        " nccccnn ",
        " sfccfns ",
        "  sssss  ",
        "         ",
    ]

    /// Embossed gold bump (dark top → gold body → light band → dark base).
    private static let minimizeGlyph = [
        "         ",
        "  sssss  ",
        " snnnnns ",
        " SGGGGGS ",
        " mMMMMMm ",
        " sSSSSSs ",
        "  sssss  ",
        "         ",
        "         ",
    ]
}
