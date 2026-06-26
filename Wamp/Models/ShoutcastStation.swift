import Foundation

/// A radio station discovered from the SHOUTcast directory.
struct ShoutcastStation: Identifiable, Codable, Equatable {
    /// Numeric station ID from the SHOUTcast Yellow Pages directory.
    let id: Int
    /// Station name (e.g. "ANTENNE BAYERN").
    let name: String
    /// Genre string (e.g. "Rock", "Electronic").
    let genre: String
    /// Stream bitrate in kbps.
    let bitrate: Int
    /// Current listener count (may be 0 if unavailable).
    let listeners: Int
    /// Audio format — "MP3" or "AAC".
    let format: String
    /// Resolved stream URL (may be nil if not yet resolved or unavailable).
    let streamURL: URL?

    // MARK: - CodingKeys

    /// Keys match the SHOUTcast directory JSON API (PascalCase).
    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case name = "Name"
        case genre = "Genre"
        case bitrate = "Bitrate"
        case listeners = "Listeners"
        case format = "Format"
        case streamURL = "StreamUrl"
    }

    // MARK: - Equatable

    /// Stations are equal if they share the same directory ID.
    static func == (lhs: ShoutcastStation, rhs: ShoutcastStation) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Display

    /// Human-readable string for UI display (e.g. "Cool Radio (192 kbps MP3)").
    var displayString: String {
        "\(name) (\(bitrate) kbps \(format))"
    }

    /// Compact listener count for the narrow station list (e.g. 5809 → "5.8K").
    var listenersDisplay: String { Self.abbreviateListeners(listeners) }

    /// Abbreviates a listener count to fit the 275px window: <1000 as-is,
    /// thousands as "5.8K" / "12K", millions as "1.5M".
    static func abbreviateListeners(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        if n < 1_000_000 {
            let k = Double(n) / 1000
            return k < 10 ? String(format: "%.1fK", k) : "\(Int(k.rounded()))K"
        }
        let m = Double(n) / 1_000_000
        return m < 10 ? String(format: "%.1fM", m) : "\(Int(m.rounded()))M"
    }
}
