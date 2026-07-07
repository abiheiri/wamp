// Wamp/Skinning/ClassicSprites/ClassicDigits.swift
// Vector recreation of NUMBERS.BMP: 9×13 seven-segment LED digits. Each cell
// is black with the display well's dot texture at even coordinates; lit
// segments are solid green lines that overwrite the dots.

import AppKit

enum ClassicDigits {
    private static let lit = NSColor(hex: 0x21FE06)
    private static let dot = NSColor(hex: 0x13191F)

    /// Segments: A top, B top-right, C bottom-right, D bottom, E bottom-left,
    /// F top-left, G middle.
    private static let segments: [[Character]] = [
        ["A", "B", "C", "D", "E", "F"],       // 0
        ["B", "C"],                           // 1
        ["A", "B", "G", "E", "D"],            // 2
        ["A", "B", "G", "C", "D"],            // 3
        ["F", "G", "B", "C"],                 // 4
        ["A", "F", "G", "C", "D"],            // 5
        ["A", "F", "G", "E", "C", "D"],       // 6
        ["A", "B", "C"],                      // 7
        ["A", "B", "C", "D", "E", "F", "G"],  // 8
        ["A", "B", "C", "D", "F", "G"],       // 9
    ]

    static func digit(_ n: Int) -> NSImage {
        let segs = segments[max(0, min(9, n))]
        return ClassicDraw.image(width: 9, height: 13) { _ in
            ClassicDraw.px(0, 0, 9, 13, .black)
            var y: CGFloat = 0
            while y <= 12 {
                var x: CGFloat = 0
                while x <= 8 {
                    ClassicDraw.px(x, y, 1, 1, dot)
                    x += 2
                }
                y += 2
            }
            // Antialias the segments: at the app's fractional window scale,
            // hard-edged 1pt columns round to different device-pixel widths
            // (the left "|" renders thinner than the right one). Soft edges
            // keep every segment visually equal.
            let ctx = NSGraphicsContext.current
            let prevAA = ctx?.shouldAntialias
            ctx?.shouldAntialias = true
            defer { if let v = prevAA { ctx?.shouldAntialias = v } }
            for seg in segs {
                switch seg {
                case "A": ClassicDraw.px(1, 0, 7, 1, lit)
                case "B": ClassicDraw.px(8, 1, 1, 5, lit)
                case "C": ClassicDraw.px(8, 7, 1, 5, lit)
                case "D": ClassicDraw.px(1, 12, 7, 1, lit)
                case "E": ClassicDraw.px(0, 7, 1, 5, lit)
                case "F": ClassicDraw.px(0, 1, 1, 5, lit)
                case "G": ClassicDraw.px(1, 6, 7, 1, lit)
                default: break
                }
            }
        }
    }
}
