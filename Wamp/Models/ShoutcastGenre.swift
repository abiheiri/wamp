import Foundation

/// A SHOUTcast directory genre. Top-level ("main") genres have `parentId == 0`
/// and carry their `subgenres`; subgenres reference their parent's id.
struct ShoutcastGenre: Codable, Equatable {
    let id: Int
    let name: String
    let parentId: Int
    var subgenres: [ShoutcastGenre]

    init(id: Int, name: String, parentId: Int, subgenres: [ShoutcastGenre] = []) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.subgenres = subgenres
    }

    var isTopLevel: Bool { parentId == 0 }

    // MARK: - Parsing

    /// Parses the directory homepage HTML into a flat genre list. The page renders
    /// each genre as an onclick handler `loadStationsByGenre('Name', id, parentId)`.
    static func parse(html: String) -> [ShoutcastGenre] {
        let pattern = #"loadStationsByGenre\('((?:[^'\\]|\\.)*)',\s*(\d+),\s*(\d+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)

        var seen = Set<Int>()
        var result: [ShoutcastGenre] = []
        regex.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match,
                  let nameR = Range(match.range(at: 1), in: html),
                  let idR = Range(match.range(at: 2), in: html),
                  let pidR = Range(match.range(at: 3), in: html),
                  let id = Int(html[idR]),
                  let parentId = Int(html[pidR]),
                  !seen.contains(id) else { return }
            seen.insert(id)
            let raw = String(html[nameR]).replacingOccurrences(of: "\\'", with: "'")
            result.append(ShoutcastGenre(id: id, name: decodeEntities(raw), parentId: parentId))
        }
        return result
    }

    /// Groups a flat list into top-level genres, each with its subgenres attached.
    static func buildTree(from flat: [ShoutcastGenre]) -> [ShoutcastGenre] {
        flat.filter { $0.parentId == 0 }.map { top in
            var t = top
            t.subgenres = flat.filter { $0.parentId == top.id }
            return t
        }
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    // MARK: - Offline fallback

    /// Bundled top-level genres used when the directory can't be reached and no
    /// cache exists. Names match real SHOUTcast primary genres (no subgenres).
    static let bundledDefaults: [ShoutcastGenre] = [
        "Alternative", "Blues", "Classical", "Country", "Decades",
        "Easy Listening", "Electronic", "Folk", "Inspirational", "International",
        "Jazz", "Latin", "Metal", "New Age", "Pop",
        "Public Radio", "R&B/Urban", "Rap", "Reggae", "Rock",
        "Seasonal/Holiday", "Soundtracks", "Talk", "Themes"
    ].enumerated().map { ShoutcastGenre(id: $0.offset + 1, name: $0.element, parentId: 0) }
}
