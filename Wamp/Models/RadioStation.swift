import Foundation

/// A radio station from any supported directory. IDs are namespaced strings so
/// stations from different directories can share one list, one favorites file,
/// and one now-playing slot: SHOUTcast stations use "sc:<numeric id>", Radio
/// Browser stations use their `stationuuid` as-is.
struct RadioStation: Identifiable, Codable, Equatable {
    enum Source: String, Codable {
        case shoutcast
        case radioBrowser
    }

    let id: String
    let source: Source
    /// Station name (e.g. "SomaFM Groove Salad").
    let name: String
    /// Genre or tag string (e.g. "Rock", "ambient").
    let genre: String
    /// Stream bitrate in kbps (0 if unknown).
    let bitrate: Int
    /// Source-relative popularity: live listeners for SHOUTcast, click count
    /// for Radio Browser. Comparable within a source, not across sources.
    let popularity: Int
    /// Audio format — "MP3" or "AAC".
    let format: String
    /// Stream URL. Always present for Radio Browser stations (`url_resolved`);
    /// may be nil for SHOUTcast stations until resolved via the directory.
    let streamURL: URL?

    init(id: String, source: Source, name: String, genre: String, bitrate: Int,
         popularity: Int, format: String, streamURL: URL?) {
        self.id = id
        self.source = source
        self.name = name
        self.genre = genre
        self.bitrate = bitrate
        self.popularity = popularity
        self.format = format
        self.streamURL = streamURL
    }

    init(from station: ShoutcastStation) {
        self.init(id: "sc:\(station.id)",
                  source: .shoutcast,
                  name: station.name,
                  genre: station.genre,
                  bitrate: station.bitrate,
                  popularity: station.listeners,
                  format: station.format,
                  streamURL: station.streamURL)
    }

    /// The numeric SHOUTcast directory ID, needed to resolve a stream URL.
    var shoutcastID: Int? {
        guard source == .shoutcast, id.hasPrefix("sc:") else { return nil }
        return Int(id.dropFirst(3))
    }

    // MARK: - Equatable

    /// Stations are equal if they share the same namespaced ID.
    static func == (lhs: RadioStation, rhs: RadioStation) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Display

    /// Human-readable string for UI display (e.g. "Cool Radio (192 kbps MP3)").
    var displayString: String {
        "\(name) (\(bitrate) kbps \(format))"
    }

    /// Compact popularity for the narrow station list (e.g. 5809 → "5.8K").
    var popularityDisplay: String {
        ShoutcastStation.abbreviateListeners(popularity)
    }

    // MARK: - Favorites decoding

    /// Decodes a favorites file in either the current `[RadioStation]` format
    /// or the legacy `[ShoutcastStation]` format (pre-Radio Browser installs),
    /// migrating legacy entries to namespaced IDs. Returns nil if neither
    /// format decodes.
    static func decodeFavorites(_ data: Data) -> [RadioStation]? {
        let decoder = JSONDecoder()
        if let current = try? decoder.decode([RadioStation].self, from: data) {
            return current
        }
        if let legacy = try? decoder.decode([ShoutcastStation].self, from: data) {
            return legacy.map(RadioStation.init(from:))
        }
        return nil
    }
}
