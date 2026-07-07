// Wamp/Skinning/ClassicSprites/BuiltInClassicSkin.swift
// The default provider: a vector recreation of the base-2.91 Winamp skin.
// Views take their skinned layout/draw paths against it, but every sprite is
// drawing-handler-backed so it rasterizes crisply at the app's 1.3× window
// scale, Double Size, and Retina — no bitmap chunkiness.

import AppKit

final class BuiltInClassicSkin: SkinProvider {
    private let cache = NSCache<NSString, NSImage>()

    func sprite(_ key: SpriteKey) -> NSImage? {
        let cacheKey = String(describing: key) as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard let image = ClassicSprites.image(key) else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    /// nil on purpose: classic built-in text renders with native fonts
    /// (TextSpriteRenderer.drawClassic fallback) so it stays crisp at 1.3×.
    var textSheet: NSImage? { nil }

    /// The genuine base-2.91 VISCOLOR.TXT palette (red top → green bottom).
    var viscolors: [NSColor] { PlaylistStyle.defaultViscolors }

    /// base-2.91 PLEDIT.TXT values — note SelectedBG is #0000C6, not pure blue.
    var playlistStyle: PlaylistStyle {
        PlaylistStyle(
            normal: NSColor(hex: 0x00FF00),
            current: .white,
            normalBG: .black,
            selectedBG: NSColor(hex: 0x0000C6),
            font: "Arial"
        )
    }

    var eqGraphLineColors: [NSColor] { [] }
    var eqPreampLineColor: NSColor { .green }
    var mainWindowRegion: NSBezierPath? { nil }
}
