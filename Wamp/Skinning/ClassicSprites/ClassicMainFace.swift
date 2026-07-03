// Wamp/Skinning/ClassicSprites/ClassicMainFace.swift
// Vector recreation of MAIN.BMP — the 275×116 main-window face: body ramp,
// beveled frame, dotted display well, marquee/kbps/kHz wells with baked
// labels, seek groove, and the gold Winamp-style emblem. All geometry and
// colors from RLE dumps of the base-2.91 sheet.

import AppKit

enum ClassicMainFace {
    static func background() -> NSImage {
        ClassicDraw.image(width: 275, height: 116) { _ in
            drawBody()
            drawFrame()
            drawDisplayWell()
            drawMarqueeWell()
            drawInfoWells()
            drawSeekGroove()
            ClassicDraw.pixelMap(kbpsLabel, at: NSPoint(x: 128, y: 42), colors: ["#": .white])
            ClassicDraw.pixelMap(kHzLabel, at: NSPoint(x: 168, y: 42), colors: ["#": .white])
            ClassicDraw.pixelMap(emblem, at: NSPoint(x: 244, y: 87), colors: emblemColors)
        }
    }

    private static func drawBody() {
        // Horizontal luminance ramp (dark edges, lighter center). The sheet's
        // vertical variation is under ±2% — not worth reproducing.
        ClassicDraw.hRamp(y: 0, height: 116, width: 275,
                          left: NSColor(hex: 0x12121B),
                          mid: NSColor(hex: 0x2A2945),
                          right: NSColor(hex: 0x1D1C2E))
    }

    private static func drawFrame() {
        ClassicDraw.windowFrame(width: 275, height: 116)
        // Inner-left bevel line of the content panel.
        ClassicDraw.px(6, 15, 1, 88, NSColor(hex: 0x4A4950))
    }

    /// The big dotted display area (time digits + visualizer draw over it).
    private static func drawDisplayWell() {
        ClassicDraw.px(11, 22, 93, 1, NSColor(hex: 0x0E0D13))
        ClassicDraw.px(11, 22, 1, 43, NSColor(hex: 0x0E0D13))
        ClassicDraw.px(12, 23, 91, 41, .black)
        let dot = NSColor(hex: 0x13121F)
        var y: CGFloat = 24
        while y <= 62 {
            var x: CGFloat = 12
            while x <= 102 {
                ClassicDraw.px(x, y, 1, 1, dot)
                x += 2
            }
            y += 2
        }
        ClassicDraw.px(12, 64, 92, 1, NSColor(hex: 0x5E5D73))
        ClassicDraw.px(103, 23, 1, 42, NSColor(hex: 0x5C5B70))
        drawBakedVisDecorations()
    }

    /// base-2.91 bakes a faint oscilloscope axis (blue dotted L) and a tiny
    /// green dash into the display well — part of the authentic face.
    private static func drawBakedVisDecorations() {
        let bright = NSColor(hex: 0x4D7FE4)
        let dim = NSColor(hex: 0x0A54A2)
        let dimmer = NSColor(hex: 0x073F71)
        var x: CGFloat = 22
        while x <= 102 {
            ClassicDraw.px(x, 60, 1, 1, Int(x - 22) % 4 == 0 ? bright : dim)
            x += 2
        }
        var y: CGFloat = 42
        while y <= 58 {
            ClassicDraw.px(22, y, 1, 1, Int(y - 42) % 4 == 0 ? dimmer : bright)
            y += 2
        }
        ClassicDraw.px(72, 30, 3, 1, NSColor(hex: 0x22FB0A))
        ClassicDraw.px(72, 32, 1, 1, NSColor(hex: 0x1A1A2A))
        ClassicDraw.px(74, 32, 1, 1, NSColor(hex: 0x1A1A2A))
    }

    private static func drawMarqueeWell() {
        ClassicDraw.px(108, 23, 159, 1, NSColor(hex: 0x1A1928))
        ClassicDraw.px(108, 23, 1, 13, NSColor(hex: 0x1A1928))
        ClassicDraw.px(109, 24, 157, 12, .black)
        ClassicDraw.px(266, 24, 1, 13, NSColor(hex: 0x555463))
        ClassicDraw.px(109, 36, 158, 1, NSColor(hex: 0x565565))
    }

    /// kbps and kHz readout wells (the numeric text draws inside them).
    private static func drawInfoWells() {
        // kbps: dark edge, 18px black, light right/bottom bevels.
        ClassicDraw.px(108, 40, 20, 1, NSColor(hex: 0x1B1A2A))
        ClassicDraw.px(108, 40, 1, 11, NSColor(hex: 0x1B1A2A))
        ClassicDraw.px(109, 41, 18, 10, .black)
        ClassicDraw.px(127, 41, 1, 11, NSColor(hex: 0x605F75))
        ClassicDraw.px(109, 51, 19, 1, NSColor(hex: 0x5E5D73))
        // kHz: same treatment, 13px interior.
        ClassicDraw.px(153, 40, 15, 1, NSColor(hex: 0x1D1C2F))
        ClassicDraw.px(153, 40, 1, 11, NSColor(hex: 0x1D1C2F))
        ClassicDraw.px(154, 41, 13, 10, .black)
        ClassicDraw.px(167, 41, 1, 11, NSColor(hex: 0x626179))
        ClassicDraw.px(154, 51, 14, 1, NSColor(hex: 0x626179))
    }

    /// Recessed groove behind the seek bar (posbar sprite covers most of it).
    private static func drawSeekGroove() {
        ClassicDraw.px(14, 71, 251, 2, NSColor(hex: 0x171623))
        ClassicDraw.px(15, 73, 249, 8, NSColor(hex: 0x232138))
        ClassicDraw.px(15, 81, 250, 1, NSColor(hex: 0x5E5D73))
        ClassicDraw.px(264, 72, 1, 9, NSColor(hex: 0x52525F))
    }

    // MARK: - Baked pixel art (extracted from MAIN.BMP)

    private static let kbpsLabel = [
        "                      ",
        "   #   #              ",
        "   #   #              ",
        "   # # ###  ##  ##    ",
        "   ##  #  # # # #     ",
        "   ##  #  # # #  #    ",
        "   # # ###  ##  ##    ",
        "            #         ",
    ]

    private static let kHzLabel = [
        "                      ",
        "   #                  ",
        "   #   #  #           ",
        "   # # #  # ####      ",
        "   ##  ####   #       ",
        "   ##  #  #  #        ",
        "   # # #  #  ###      ",
        "                      ",
    ]

    private static let emblem = [
        "abccddeefffghgggiijjklm",
        "noodcppfffqghgggjijkrss",
        "bocdpepffqqggttgiikkrss",
        "aoopdppffqqguvvtjjwxysm",
        "oocppefffqquvzzvtyABAss",
        "occppefqfquvzzzCADEFAmm",
        "oodpffeqquvzzGvDHEFAImm",
        "oddppffquvzJKDFHEFAtsmm",
        "ocppeffuvzLDFHHHFALvtmm",
        "odpepfuvzMNHHHEHHFMzvtm",
        "ddpeeuvzzDHHHOEHFFNzzvt",
        "dppeeuvzzDFHOEFFFFPzzvt",
        "dpppffuvzMDOHFHFDMGzvtQ",
        "dpefqfguvPOFFFFARzzvtww",
        "pefffqqjSEFHFDMGzzvtTTT",
        "peefqqjSEFFFALzzzvtmmQU",
        "eeffqgxEHFDVJzzzvtmwWTT",
        "eefqqqxFFXYtvzzvtmmwQTU",
    ]

    private static let emblemColors: [Character: NSColor] = [
        "A": NSColor(hex: 0x29220E), "B": NSColor(hex: 0x74653C),
        "C": NSColor(hex: 0x677476), "D": NSColor(hex: 0x473416),
        "E": NSColor(hex: 0x967C44), "F": NSColor(hex: 0x955118),
        "G": NSColor(hex: 0x7C7D80), "H": NSColor(hex: 0x957325),
        "I": NSColor(hex: 0x161622), "J": NSColor(hex: 0x908E9D),
        "K": NSColor(hex: 0x4A4950), "L": NSColor(hex: 0x646464),
        "M": NSColor(hex: 0x33322A), "N": NSColor(hex: 0x524933),
        "O": NSColor(hex: 0x928358), "P": NSColor(hex: 0x3D362E),
        "Q": NSColor(hex: 0x171825), "R": NSColor(hex: 0x4F4F5A),
        "S": NSColor(hex: 0x23241C), "T": NSColor(hex: 0x181725),
        "U": NSColor(hex: 0x171724), "V": NSColor(hex: 0x101010),
        "W": NSColor(hex: 0x171726), "X": NSColor(hex: 0x1C160A),
        "Y": NSColor(hex: 0x161520),
        "a": NSColor(hex: 0x1D1C2F), "b": NSColor(hex: 0x1D1D2F),
        "c": NSColor(hex: 0x1C1C2E), "d": NSColor(hex: 0x1C1B2E),
        "e": NSColor(hex: 0x1C1B2D), "f": NSColor(hex: 0x1C1B2C),
        "g": NSColor(hex: 0x1B1A2A), "h": NSColor(hex: 0x1A1A2A),
        "i": NSColor(hex: 0x1A1A29), "j": NSColor(hex: 0x1A1928),
        "k": NSColor(hex: 0x1A1827), "l": NSColor(hex: 0x191827),
        "m": NSColor(hex: 0x181726), "n": NSColor(hex: 0x1E1C2F),
        "o": NSColor(hex: 0x1E1C2E), "p": NSColor(hex: 0x1C1C2D),
        "q": NSColor(hex: 0x1B1A2B), "r": NSColor(hex: 0x191927),
        "s": NSColor(hex: 0x1A1826), "t": NSColor(hex: 0x101015),
        "u": NSColor(hex: 0x101016), "v": NSColor(hex: 0x383838),
        "w": NSColor(hex: 0x181825), "x": NSColor(hex: 0x12121A),
        "y": NSColor(hex: 0x14141D), "z": NSColor(hex: 0x9D9FA6),
    ]
}
