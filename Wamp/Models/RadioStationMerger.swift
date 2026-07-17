import Foundation

/// Combines station lists from the two directories into the single ranked list
/// the UI shows. Pure functions only — no I/O, no state.
enum RadioStationMerger {

    /// Canonical form of a station name for cross-directory duplicate detection:
    /// lowercased, punctuation removed, and bitrate/format decoration tokens
    /// ("128k", "128kbps", "mp3", "aac") dropped. Bare numbers are kept — they
    /// distinguish real stations ("BBC Radio 1" vs "BBC Radio 2").
    static func normalizedName(_ name: String) -> String {
        let dropped: Set<String> = ["kbps", "mp3", "aac"]
        return name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                guard !token.isEmpty, !dropped.contains(token) else { return false }
                if token.hasSuffix("k") || token.hasSuffix("kbps") {
                    let digits = token.hasSuffix("kbps") ? token.dropLast(4) : token.dropLast(1)
                    if !digits.isEmpty, digits.allSatisfy(\.isNumber) { return false }
                }
                return true
            }
            .joined()
    }

    /// Interleaves two independently ranked lists rank-by-rank (a[0], b[0],
    /// a[1], b[1], …) so neither directory dominates the merged view, dropping
    /// duplicates by normalized name — the first (better-ranked) copy wins.
    /// Popularity numbers are source-relative, so rank position is the only
    /// fair ordering across directories.
    static func merged(_ a: [RadioStation], _ b: [RadioStation]) -> [RadioStation] {
        var seen = Set<String>()
        var result: [RadioStation] = []
        result.reserveCapacity(a.count + b.count)
        for rank in 0..<max(a.count, b.count) {
            for list in [a, b] where rank < list.count {
                let station = list[rank]
                let key = normalizedName(station.name)
                if seen.insert(key).inserted {
                    result.append(station)
                }
            }
        }
        return result
    }
}
