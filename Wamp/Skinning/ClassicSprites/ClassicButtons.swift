// Wamp/Skinning/ClassicSprites/ClassicButtons.swift
// Wraps the generated ClassicPixelSheets maps as drawing-handler images for
// the transport buttons, shuffle/repeat, EQ/PL toggles, and mono/stereo
// indicators.

import AppKit

enum ClassicButtons {
    static func fromSheet(_ map: [String]) -> NSImage {
        let h = map.count
        let w = map.first.map { $0.count } ?? 0
        return ClassicDraw.image(width: w, height: h) { _ in
            ClassicDraw.pixelMap(map, at: .zero, colors: ClassicPixelSheets.colors)
        }
    }

    static func transport(_ key: SpriteKey) -> NSImage? {
        switch key {
        case .previous(let p): return fromSheet(p ? ClassicPixelSheets.btnPreviousPressed : ClassicPixelSheets.btnPrevious)
        case .play(let p):     return fromSheet(p ? ClassicPixelSheets.btnPlayPressed : ClassicPixelSheets.btnPlay)
        case .pause(let p):    return fromSheet(p ? ClassicPixelSheets.btnPausePressed : ClassicPixelSheets.btnPause)
        case .stop(let p):     return fromSheet(p ? ClassicPixelSheets.btnStopPressed : ClassicPixelSheets.btnStop)
        case .next(let p):     return fromSheet(p ? ClassicPixelSheets.btnNextPressed : ClassicPixelSheets.btnNext)
        case .eject(let p):    return fromSheet(p ? ClassicPixelSheets.btnEjectPressed : ClassicPixelSheets.btnEject)
        default: return nil
        }
    }

    static func toggle(_ key: SpriteKey) -> NSImage? {
        switch key {
        case .shuffleButton(let active, let pressed):
            return fromSheet(pick(active, pressed,
                                  ClassicPixelSheets.shuffleOff, ClassicPixelSheets.shuffleOffPressed,
                                  ClassicPixelSheets.shuffleOn, ClassicPixelSheets.shuffleOnPressed))
        case .repeatButton(let active, let pressed):
            return fromSheet(pick(active, pressed,
                                  ClassicPixelSheets.repeatOff, ClassicPixelSheets.repeatOffPressed,
                                  ClassicPixelSheets.repeatOn, ClassicPixelSheets.repeatOnPressed))
        case .eqToggleButton(let active, let pressed):
            return fromSheet(pick(active, pressed,
                                  ClassicPixelSheets.eqOff, ClassicPixelSheets.eqOffPressed,
                                  ClassicPixelSheets.eqOn, ClassicPixelSheets.eqOnPressed))
        case .plToggleButton(let active, let pressed):
            return fromSheet(pick(active, pressed,
                                  ClassicPixelSheets.plOff, ClassicPixelSheets.plOffPressed,
                                  ClassicPixelSheets.plOn, ClassicPixelSheets.plOnPressed))
        case .mono(let active):
            return fromSheet(active ? ClassicPixelSheets.monoOn : ClassicPixelSheets.monoOff)
        case .stereo(let active):
            return fromSheet(active ? ClassicPixelSheets.stereoOn : ClassicPixelSheets.stereoOff)
        default: return nil
        }
    }

    private static func pick(_ active: Bool, _ pressed: Bool,
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
