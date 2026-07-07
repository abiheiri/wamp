// Wamp/Skinning/ClassicSprites/ClassicButtons.swift
// Structural (vector) recreations of CBUTTONS/SHUFREP/MONOSTER and the EQ
// buttons. Pixel maps reproduce the bitmap-skin chunkiness at the app's
// fractional 1.3× scale, so button chrome is drawn as continuous bevels,
// path-based icons, and native-font labels — crisp at any backing scale.

import AppKit

enum ClassicButtons {
    // Silver family sampled from CBUTTONS.BMP.
    private static let face = NSColor(hex: 0xB0C3CD)
    private static let facePressed = NSColor(hex: 0xA3B5C0)
    private static let edgeLight = NSColor(hex: 0xEBFFFF)
    private static let edgeOuter = NSColor(hex: 0x9DA6BA)
    private static let shadowMid = NSColor(hex: 0x718194)
    private static let shadowDark = NSColor(hex: 0x3A4858)
    private static let iconFill = NSColor(hex: 0x8597AB)
    private static let iconEdge = NSColor(hex: 0x3A4858)
    private static let labelColor = NSColor(hex: 0x2E374C)
    private static let ledLit = NSColor(hex: 0x16B008)
    private static let ledDim = NSColor(hex: 0x0F5A00)

    static func fromSheet(_ map: [String],
                          colors: [Character: NSColor] = [:]) -> NSImage {
        let h = map.count
        let w = map.first.map { $0.count } ?? 0
        return ClassicDraw.image(width: w, height: h) { _ in
            ClassicDraw.pixelMap(map, at: .zero, colors: colors)
        }
    }

    // MARK: - Shared chrome

    /// Raised (or pressed-in) silver button face with the CBUTTONS bevel:
    /// light on top/left, stepped mid+dark shadow on bottom/right.
    static func drawSilverFace(_ rect: NSRect, pressed: Bool) {
        ClassicDraw.px(rect.minX, rect.minY, rect.width, rect.height,
                       pressed ? facePressed : face)
        let light = pressed ? shadowDark : edgeLight
        let darkA = pressed ? edgeLight : shadowMid
        let darkB = pressed ? edgeOuter : shadowDark
        // outer edge ring
        ClassicDraw.px(rect.minX, rect.minY, rect.width, 1, edgeOuter)
        ClassicDraw.px(rect.minX, rect.minY, 1, rect.height, edgeOuter)
        // light bevel (top + left, inside the ring)
        ClassicDraw.px(rect.minX + 1, rect.minY + 1, rect.width - 2, 1, light)
        ClassicDraw.px(rect.minX + 1, rect.minY + 1, 1, rect.height - 2, light)
        // stepped shadow (bottom + right)
        ClassicDraw.px(rect.minX + 1, rect.maxY - 2, rect.width - 1, 1, darkA)
        ClassicDraw.px(rect.maxX - 2, rect.minY + 1, 1, rect.height - 2, darkA)
        ClassicDraw.px(rect.minX, rect.maxY - 1, rect.width, 1, darkB)
        ClassicDraw.px(rect.maxX - 1, rect.minY, 1, rect.height, darkB)
    }

    private static func label(_ text: String, in rect: NSRect, size: CGFloat = 6.5,
                              color: NSColor = labelColor, offset: NSPoint = .zero) {
        let ctx = NSGraphicsContext.current
        let prevAA = ctx?.shouldAntialias
        ctx?.shouldAntialias = true
        defer { if let v = prevAA { ctx?.shouldAntialias = v } }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: color,
        ]
        let s = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: rect.midX - s.width / 2 + offset.x,
                              y: rect.midY - s.height / 2 + offset.y),
                  withAttributes: attrs)
    }

    /// Small square LED with a bevel well, lit green when active.
    private static func drawLED(at p: NSPoint, active: Bool) {
        ClassicDraw.px(p.x, p.y, 5, 5, NSColor(hex: 0x23293C))
        ClassicDraw.px(p.x + 1, p.y + 1, 3, 3, active ? ledLit : ledDim)
        ClassicDraw.px(p.x + 1, p.y + 1, 3, 1, active ? NSColor(hex: 0x49E23B) : NSColor(hex: 0x1A6B12))
    }

    private static func fillPath(_ points: [(CGFloat, CGFloat)], offset: NSPoint) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: points[0].0 + offset.x, y: points[0].1 + offset.y))
        for p in points.dropFirst() {
            path.line(to: NSPoint(x: p.0 + offset.x, y: p.1 + offset.y))
        }
        path.close()
        iconFill.setFill()
        path.fill()
        iconEdge.setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }

    // MARK: - Transport (cbuttons)

    static func transport(_ key: SpriteKey) -> NSImage? {
        switch key {
        case .previous(let p): return transportButton(width: 23, height: 18, pressed: p, icon: previousIcon)
        case .play(let p):     return transportButton(width: 23, height: 18, pressed: p, icon: playIcon)
        case .pause(let p):    return transportButton(width: 23, height: 18, pressed: p, icon: pauseIcon)
        case .stop(let p):     return transportButton(width: 23, height: 18, pressed: p, icon: stopIcon)
        case .next(let p):     return transportButton(width: p ? 22 : 23, height: 18, pressed: p, icon: nextIcon)
        case .eject(let p):    return transportButton(width: 22, height: 16, pressed: p, icon: ejectIcon)
        default: return nil
        }
    }

    private static func transportButton(width: Int, height: Int, pressed: Bool,
                                        icon: @escaping (NSPoint) -> Void) -> NSImage {
        ClassicDraw.image(width: width, height: height) { rect in
            drawSilverFace(NSRect(x: 0, y: 0, width: rect.width, height: rect.height),
                           pressed: pressed)
            icon(pressed ? NSPoint(x: 1, y: 1) : .zero)
        }
    }

    // Icon geometry follows the CBUTTONS sheet (Winamp Y-down coordinates).
    private static func previousIcon(_ o: NSPoint) {
        ClassicDraw.px(6 + o.x, 4 + o.y, 2.5, 10, iconFill)
        fillPath([(15.5, 4), (15.5, 14), (9.5, 9)], offset: o)
    }
    private static func playIcon(_ o: NSPoint) {
        fillPath([(8, 4), (8, 14), (15, 9)], offset: o)
    }
    private static func pauseIcon(_ o: NSPoint) {
        ClassicDraw.px(7 + o.x, 4 + o.y, 3, 10, iconFill)
        ClassicDraw.px(13 + o.x, 4 + o.y, 3, 10, iconFill)
    }
    private static func stopIcon(_ o: NSPoint) {
        ClassicDraw.px(7.5 + o.x, 5 + o.y, 8, 8, iconFill)
    }
    private static func nextIcon(_ o: NSPoint) {
        fillPath([(7, 4), (7, 14), (13, 9)], offset: o)
        ClassicDraw.px(14.5 + o.x, 4 + o.y, 2.5, 10, iconFill)
    }
    private static func ejectIcon(_ o: NSPoint) {
        fillPath([(11, 3.5), (16, 9), (6, 9)], offset: o)
        ClassicDraw.px(6 + o.x, 11 + o.y, 10, 2, iconFill)
    }

    // MARK: - Toggles (shufrep, monoster)

    static func toggle(_ key: SpriteKey) -> NSImage? {
        switch key {
        case .shuffleButton(let active, let pressed):
            return ledTextButton(width: 47, height: 15, text: "SHUFFLE", active: active, pressed: pressed)
        case .repeatButton(let active, let pressed):
            return repeatButton(active: active, pressed: pressed)
        case .eqToggleButton(let active, let pressed):
            return ledTextButton(width: 23, height: 12, text: "EQ", active: active, pressed: pressed)
        case .plToggleButton(let active, let pressed):
            return ledTextButton(width: 23, height: 12, text: "PL", active: active, pressed: pressed)
        case .mono(let active):
            return indicatorText(width: 27, text: "mono", active: active)
        case .stereo(let active):
            return indicatorText(width: 29, text: "stereo", active: active)
        default: return nil
        }
    }

    /// Silver button with a LED at the left and a native-font label —
    /// the SHUFFLE/REP/EQ/PL/ON/AUTO family.
    static func ledTextButton(width: Int, height: Int, text: String,
                              active: Bool, pressed: Bool) -> NSImage {
        ClassicDraw.image(width: width, height: height) { rect in
            drawSilverFace(NSRect(x: 0, y: 0, width: rect.width, height: rect.height),
                           pressed: pressed)
            let o: CGFloat = pressed ? 1 : 0
            drawLED(at: NSPoint(x: 3 + o, y: (rect.height - 5) / 2 + o), active: active)
            let textRect = NSRect(x: 8, y: 0, width: rect.width - 9, height: rect.height)
            label(text, in: textRect, offset: NSPoint(x: o, y: o))
        }
    }

    /// Repeat toggle: LED plus the classic circular loop-arrow glyph.
    private static func repeatButton(active: Bool, pressed: Bool) -> NSImage {
        ClassicDraw.image(width: 28, height: 15) { rect in
            drawSilverFace(NSRect(x: 0, y: 0, width: rect.width, height: rect.height),
                           pressed: pressed)
            let o: CGFloat = pressed ? 1 : 0
            drawLED(at: NSPoint(x: 3 + o, y: (rect.height - 5) / 2 + o), active: active)

            let ctx = NSGraphicsContext.current
            let prevAA = ctx?.shouldAntialias
            ctx?.shouldAntialias = true
            defer { if let v = prevAA { ctx?.shouldAntialias = v } }

            // Open loop: stroke the ring, break its bottom-left arc by
            // painting the face color back over it, then terminate the line
            // with a left-pointing arrowhead at the break.
            let loop = NSBezierPath(roundedRect: NSRect(x: 12 + o, y: 4.5 + o, width: 12, height: 6),
                                    xRadius: 3, yRadius: 3)
            loop.lineWidth = 1.2
            labelColor.setStroke()
            loop.stroke()

            NSColor(hex: pressed ? 0xA3B5C0 : 0xB0C3CD).setFill()
            NSRect(x: 11 + o, y: 7.5 + o, width: 5, height: 4.5).fill()

            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: 13.5 + o, y: 10.5 + o))
            arrow.line(to: NSPoint(x: 17.5 + o, y: 8 + o))
            arrow.line(to: NSPoint(x: 17.5 + o, y: 13 + o))
            arrow.close()
            labelColor.setFill()
            arrow.fill()
        }
    }

    /// mono / stereo readouts: label only, lit green when active.
    private static func indicatorText(width: Int, text: String, active: Bool) -> NSImage {
        ClassicDraw.image(width: width, height: 12) { rect in
            label(text, in: NSRect(x: 0, y: 0, width: rect.width, height: rect.height),
                  size: 7,
                  color: active ? NSColor(hex: 0x20E111) : NSColor(hex: 0x636276))
        }
    }

    /// PRESETS-style plain text button.
    static func textButton(width: Int, height: Int, text: String, pressed: Bool) -> NSImage {
        ClassicDraw.image(width: width, height: height) { rect in
            drawSilverFace(NSRect(x: 0, y: 0, width: rect.width, height: rect.height),
                           pressed: pressed)
            let o: CGFloat = pressed ? 1 : 0
            label(text, in: NSRect(x: 0, y: 0, width: rect.width, height: rect.height),
                  offset: NSPoint(x: o, y: o))
        }
    }
}
