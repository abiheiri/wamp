import Foundation

/// Parsed ICY (SHOUTcast) inline metadata from a streaming audio connection.
struct ICYMetadata: Equatable {
    /// Current track title (e.g. "Artist - Song").
    let streamTitle: String
    /// Stream URL from metadata, if present.
    let streamUrl: String?
}

/// Parses ICY (I Can Yell) inline metadata embedded in SHOUTcast/ICEcast streams.
/// All methods are pure — no shared mutable state.
enum ICYMetadataParser {

    // MARK: - HTTP Header

    /// Extract the `icy-metaint` value (metadata interval in bytes) from HTTP response headers.
    /// Returns 0 if the header is absent or unparseable (meaning no metadata).
    nonisolated static func metadataInterval(from headers: [String: String]) -> Int {
        guard let raw = headers["icy-metaint"],
              let interval = Int(raw),
              interval > 0 else { return 0 }
        return interval
    }

    // MARK: - Parse Metadata Block

    /// Parse a raw ICY metadata byte block into a structured `ICYMetadata`.
    /// Block format (after length byte):
    ///   `StreamTitle='...';StreamUrl='...';` (null-padded to length*16 bytes)
    /// Returns nil if no meaningful metadata was found.
    nonisolated static func parse(_ data: Data) -> ICYMetadata? {
        guard !data.isEmpty else { return nil }

        // Trim null padding
        let trimmed = data.filter { $0 != 0 }
        guard let raw = String(data: Data(trimmed), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        let title = extractValue(for: "StreamTitle", from: raw)
        let url = extractValue(for: "StreamUrl", from: raw)

        // If there's no title and no url, treat as no metadata
        if title == nil && url == nil { return nil }

        return ICYMetadata(streamTitle: title ?? "", streamUrl: url)
    }

    // MARK: - Private

    /// Extract a key='value' pair from a semicolon-delimited ICY metadata string.
    /// Handles escaped single quotes inside values (e.g. `Don\'t`).
    private nonisolated static func extractValue(for key: String, from raw: String) -> String? {
        let pattern = #"\#(key)='((?:[^'\\]|\\.)*)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: raw, options: [], range: NSRange(raw.startIndex..., in: raw)),
              let valueRange = Range(match.range(at: 1), in: raw) else { return nil }

        let rawValue = String(raw[valueRange])
        // Unescape \' → '
        return rawValue.replacingOccurrences(of: "\\'", with: "'")
    }
}
