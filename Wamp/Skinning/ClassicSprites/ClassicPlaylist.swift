// Wamp/Skinning/ClassicSprites/ClassicPlaylist.swift
// Vector recreation of PLEDIT.BMP chrome: top strip with gold pipes and
// title plate, side tiles, bottom corners (running-time LCD + mini
// transport), and the scroll handle. The ADD/REM/SEL/MISC/LISTS controls are
// Wamp's own WinampButtons drawn over the plain bottom-left corner.

import AppKit

enum ClassicPlaylist {
    private static let body = NSColor(hex: 0x26253F)
    private static let edgeDark = NSColor(hex: 0x0C0C10)
    private static let edgeLight = NSColor(hex: 0x4F4F5A)
    private static let innerDark = NSColor(hex: 0x131420)
    private static let bottomShade = NSColor(hex: 0x1C1B2C)

    // MARK: - Top strip (20 px tall)

    static func topTile(active: Bool) -> NSImage {
        ClassicDraw.image(width: 25, height: 20) { rect in
            drawTopBody(width: rect.width)
            drawPipes(from: 0, to: rect.width, active: active)
        }
    }

    static func topCorner(left: Bool, active: Bool) -> NSImage {
        ClassicDraw.image(width: 25, height: 20) { rect in
            drawTopBody(width: rect.width)
            if left {
                drawPipes(from: 4, to: rect.width, active: active)
                ClassicDraw.px(0, 0, 1, 20, edgeDark)
                ClassicDraw.px(1, 1, 1, 19, edgeLight)
            } else {
                // Pipes stop short of the baked close glyph.
                drawPipes(from: 0, to: 11, active: active)
                ClassicTitleBar.drawCloseGlyph(at: NSPoint(x: 13, y: 5))
                ClassicDraw.px(24, 0, 1, 20, NSColor(hex: 0x14141D))
                ClassicDraw.px(23, 1, 1, 19, NSColor(hex: 0x52525F))
            }
        }
    }

    static func titleBar(active: Bool) -> NSImage {
        ClassicDraw.image(width: 100, height: 20) { rect in
            drawTopBody(width: rect.width)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: WinampTheme.titleBarFont,
                .foregroundColor: active ? ClassicPalette.titleTextActive
                                         : ClassicPalette.titleTextInactive,
                .kern: 1.2,
            ]
            let title = "PLAYLIST"
            let size = title.size(withAttributes: attrs)
            let tx = (rect.width - size.width) / 2
            drawPipes(from: 0, to: tx - 4, active: active)
            drawPipes(from: tx + size.width + 4, to: rect.width, active: active)
            title.draw(at: NSPoint(x: tx, y: (20 - size.height) / 2), withAttributes: attrs)
        }
    }

    private static func drawTopBody(width: CGFloat) {
        ClassicDraw.px(0, 0, width, 20, body)
        ClassicDraw.px(0, 0, width, 1, edgeDark)
        ClassicDraw.px(0, 1, width, 1, NSColor(hex: 0x565565))
        ClassicDraw.px(0, 18, width, 1, bottomShade)
        ClassicDraw.px(0, 19, width, 1, innerDark)
    }

    /// The same embossed gold pipe rows as the main titlebar, centered in
    /// the 20px strip (rows 6..12). Tiles continue the run seamlessly.
    private static func drawPipes(from x0: CGFloat, to x1: CGFloat, active: Bool) {
        guard x1 - x0 >= 3 else { return }
        let rows = active ? ClassicPalette.pipeActive : ClassicPalette.pipeInactive
        for (i, color) in rows.enumerated() {
            ClassicDraw.px(x0, 6 + CGFloat(i), x1 - x0, 1, color)
        }
    }

    // MARK: - Side tiles

    static func leftTile() -> NSImage {
        ClassicDraw.image(width: 12, height: 29) { _ in
            ClassicDraw.px(0, 0, 12, 29, body)
            ClassicDraw.px(0, 0, 1, 29, edgeDark)
            ClassicDraw.px(1, 0, 1, 29, edgeLight)
            ClassicDraw.px(11, 0, 1, 29, innerDark)
        }
    }

    static func rightTile() -> NSImage {
        ClassicDraw.image(width: 20, height: 29) { _ in
            ClassicDraw.px(0, 0, 20, 29, body)
            ClassicDraw.px(0, 0, 1, 29, innerDark)
            // Scroll channel behind the 8px handle (local x 6..14).
            ClassicDraw.px(5, 0, 1, 29, NSColor(hex: 0x0F0F16))
            ClassicDraw.px(6, 0, 9, 29, NSColor(hex: 0x1A1929))
            ClassicDraw.px(15, 0, 1, 29, NSColor(hex: 0x52525F))
            ClassicDraw.px(18, 0, 1, 29, NSColor(hex: 0x52525F))
            ClassicDraw.px(19, 0, 1, 29, NSColor(hex: 0x14141D))
        }
    }

    // MARK: - Bottom strip (38 px tall)

    static func bottomTile() -> NSImage {
        ClassicDraw.image(width: 25, height: 38) { rect in
            drawBottomBody(width: rect.width)
        }
    }

    static func bottomLeftCorner() -> NSImage {
        ClassicDraw.image(width: 125, height: 38) { rect in
            drawBottomBody(width: rect.width)
            ClassicDraw.px(0, 0, 1, 38, edgeDark)
            ClassicDraw.px(1, 0, 1, 37, edgeLight)
        }
    }

    static func bottomRightCorner() -> NSImage {
        ClassicDraw.image(width: 150, height: 38) { rect in
            drawBottomBody(width: rect.width)
            ClassicDraw.px(149, 0, 1, 38, NSColor(hex: 0x14141D))
            ClassicDraw.px(148, 0, 1, 37, NSColor(hex: 0x52525F))
            // Running-time LCD well (drawClassic renders the text inside).
            ClassicDraw.px(4, 8, 79, 1, innerDark)
            ClassicDraw.px(4, 8, 1, 12, innerDark)
            ClassicDraw.px(5, 9, 78, 11, .black)
            ClassicDraw.px(83, 9, 1, 11, NSColor(hex: 0x565565))
            ClassicDraw.px(5, 20, 79, 1, NSColor(hex: 0x565565))
            // Mini transport row at the hit rects PlaylistView routes
            // (local x = 3 + 10i, y = 22, 10×10 each).
            let icons: [(NSPoint) -> Void] = [miniPrev, miniPlay, miniPause,
                                              miniStop, miniNext, miniEject]
            for (i, icon) in icons.enumerated() {
                let x = CGFloat(3 + i * 10)
                ClassicButtons.drawSilverFace(NSRect(x: x, y: 22, width: 10, height: 10),
                                              pressed: false)
                icon(NSPoint(x: x, y: 22))
            }
        }
    }

    private static func drawBottomBody(width: CGFloat) {
        ClassicDraw.px(0, 0, width, 38, body)
        ClassicDraw.px(0, 0, width, 1, innerDark)
        ClassicDraw.px(0, 1, width, 1, NSColor(hex: 0x3B3A55))
        ClassicDraw.px(0, 36, width, 1, bottomShade)
        ClassicDraw.px(0, 37, width, 1, edgeDark)
    }

    // Tiny navy glyphs for the mini transport buttons.
    private static let miniIcon = NSColor(hex: 0x2E374C)
    private static func miniTriangle(_ o: NSPoint, pointingRight: Bool) {
        let path = NSBezierPath()
        if pointingRight {
            path.move(to: NSPoint(x: o.x + 3, y: o.y + 2.5))
            path.line(to: NSPoint(x: o.x + 3, y: o.y + 7.5))
            path.line(to: NSPoint(x: o.x + 7, y: o.y + 5))
        } else {
            path.move(to: NSPoint(x: o.x + 7, y: o.y + 2.5))
            path.line(to: NSPoint(x: o.x + 7, y: o.y + 7.5))
            path.line(to: NSPoint(x: o.x + 3, y: o.y + 5))
        }
        path.close()
        miniIcon.setFill()
        path.fill()
    }
    private static func miniPrev(_ o: NSPoint) {
        ClassicDraw.px(o.x + 2.5, o.y + 3, 1, 4, miniIcon)
        miniTriangle(NSPoint(x: o.x + 0.5, y: o.y), pointingRight: false)
    }
    private static func miniPlay(_ o: NSPoint) { miniTriangle(o, pointingRight: true) }
    private static func miniPause(_ o: NSPoint) {
        ClassicDraw.px(o.x + 3, o.y + 3, 1.5, 4, miniIcon)
        ClassicDraw.px(o.x + 5.5, o.y + 3, 1.5, 4, miniIcon)
    }
    private static func miniStop(_ o: NSPoint) {
        ClassicDraw.px(o.x + 3, o.y + 3, 4, 4, miniIcon)
    }
    private static func miniNext(_ o: NSPoint) {
        miniTriangle(NSPoint(x: o.x - 0.5, y: o.y), pointingRight: true)
        ClassicDraw.px(o.x + 6.5, o.y + 3, 1, 4, miniIcon)
    }
    private static func miniEject(_ o: NSPoint) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: o.x + 5, y: o.y + 2.5))
        path.line(to: NSPoint(x: o.x + 7.5, y: o.y + 5.5))
        path.line(to: NSPoint(x: o.x + 2.5, y: o.y + 5.5))
        path.close()
        miniIcon.setFill()
        path.fill()
        ClassicDraw.px(o.x + 2.5, o.y + 6.5, 5, 1, miniIcon)
    }

    // MARK: - Scroll handle

    static func scrollHandle(pressed: Bool) -> NSImage {
        ClassicDraw.image(width: 8, height: 18) { _ in
            let face = NSColor(hex: pressed ? 0x10151B : 0x9DAEB7)
            ClassicDraw.px(0, 0, 8, 18, NSColor(hex: 0x0B0D11))
            ClassicDraw.px(1, 1, 6, 16, face)
            ClassicDraw.px(1, 1, 6, 1, NSColor(hex: 0xD2E1E5))
            ClassicDraw.px(1, 1, 1, 16, NSColor(hex: 0xD2E1E5))
            if !pressed {
                ClassicDraw.px(1, 16, 6, 1, NSColor(hex: 0x3A4858))
                ClassicDraw.px(6, 1, 1, 16, NSColor(hex: 0x687082))
            }
            let grip = NSColor(hex: pressed ? 0xFFFFFF : 0x0B0D11)
            ClassicDraw.px(2, 7.5, 4, 1, grip)
            ClassicDraw.px(2, 10, 4, 1, grip)
        }
    }
}
