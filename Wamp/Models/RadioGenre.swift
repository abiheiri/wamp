import Foundation

/// One entry in the combined genre menu. Selecting it queries SHOUTcast by
/// `shoutcastGenre` (when set) and Radio Browser by each of `tags` — either
/// side may be absent, which just means one directory sits that genre out.
struct RadioGenre: Codable, Equatable {
    /// Display name shown in the menu.
    let name: String
    /// SHOUTcast browse key; nil for genres that exist only in Radio Browser.
    let shoutcastGenre: String?
    /// Radio Browser tags to query; empty for SHOUTcast-only genres.
    let tags: [String]
    var subgenres: [RadioGenre]

    init(name: String, shoutcastGenre: String?, tags: [String], subgenres: [RadioGenre] = []) {
        self.name = name
        self.shoutcastGenre = shoutcastGenre
        self.tags = tags
        self.subgenres = subgenres
    }
}

/// Builds the seamless genre menu: the curated SHOUTcast tree is the skeleton,
/// and popular Radio Browser tags fold in as extra subgenres (or a trailing
/// "More genres" group) so scenes SHOUTcast never indexed stay browsable.
enum RadioGenreUnion {

    /// SHOUTcast genre name → Radio Browser tags, where the default (lowercased
    /// name) wouldn't match the community's tagging.
    static let aliases: [String: [String]] = [
        "R&B/Urban": ["rnb"],
        "Rap": ["hip hop"],
        "International": ["world music"],
        "Seasonal/Holiday": ["christmas"],
        "Soundtracks": ["soundtrack"],
        "Inspirational": ["christian"],
        "Decades": ["oldies"],
    ]

    /// Radio Browser tag → SHOUTcast top-level genre it folds under. Tags not
    /// listed here (and not already covered) land in "More genres".
    static let tagParents: [String: String] = [
        "synthwave": "Electronic", "lofi": "Electronic", "house": "Electronic",
        "techno": "Electronic", "trance": "Electronic", "edm": "Electronic",
        "drum and bass": "Electronic", "dubstep": "Electronic", "chillout": "Electronic",
        "k-pop": "Pop", "j-pop": "Pop", "top 40": "Pop", "hits": "Pop",
        "indie": "Alternative", "indie rock": "Alternative",
        "classic rock": "Rock", "hard rock": "Rock",
        "smooth jazz": "Jazz",
        "oldies": "Decades", "80s": "Decades", "90s": "Decades", "70s": "Decades", "60s": "Decades",
        "news": "Talk", "sports": "Talk",
        "salsa": "Latin", "reggaeton": "Latin",
        "schlager": "International", "bollywood": "International",
        "gospel": "Inspirational",
        "hip hop": "Rap",
    ]

    /// Tags too generic to mean anything as a genre — hugely popular in the
    /// community data but useless as menu entries.
    static let ignoredTags: Set<String> = [
        "music", "radio", "fm", "am", "various", "local", "misc", "other",
        "musica", "música", "estación", "estacion", "entertainment", "juvenil",
    ]

    /// Default Radio Browser tags for a SHOUTcast genre name.
    private static func tagsFor(scGenre name: String) -> [String] {
        aliases[name] ?? [name.lowercased()]
    }

    /// "k-pop" → "K-Pop", "hip hop" → "Hip Hop".
    static func displayName(forTag tag: String) -> String {
        tag.split(whereSeparator: { $0 == " " || $0 == "-" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: tag.contains("-") ? "-" : " ")
    }

    static func build(shoutcastTree: [ShoutcastGenre],
                      topTags: [RadioBrowserTag],
                      minStationCount: Int = 100) -> [RadioGenre] {
        let skeleton = shoutcastTree.isEmpty ? ShoutcastGenre.bundledDefaults : shoutcastTree
        var union = skeleton.map { top in
            RadioGenre(name: top.name,
                       shoutcastGenre: top.name,
                       tags: tagsFor(scGenre: top.name),
                       subgenres: top.subgenres.map {
                           RadioGenre(name: $0.name, shoutcastGenre: $0.name,
                                      tags: tagsFor(scGenre: $0.name))
                       })
        }

        // Everything the skeleton already queries or displays, so a top tag
        // like "rock" doesn't reappear as a duplicate menu entry.
        var covered = Set<String>()
        for genre in union {
            covered.insert(genre.name.lowercased())
            covered.formUnion(genre.tags)
            for sub in genre.subgenres {
                covered.insert(sub.name.lowercased())
                covered.formUnion(sub.tags)
            }
        }

        var leftovers: [RadioGenre] = []
        for tag in topTags where tag.stationcount >= minStationCount {
            guard !covered.contains(tag.name), !ignoredTags.contains(tag.name) else { continue }
            covered.insert(tag.name)
            let entry = RadioGenre(name: displayName(forTag: tag.name),
                                   shoutcastGenre: nil,
                                   tags: [tag.name])
            if let parentName = tagParents[tag.name],
               let idx = union.firstIndex(where: { $0.name == parentName }) {
                union[idx].subgenres.append(entry)
            } else {
                leftovers.append(entry)
            }
        }

        if !leftovers.isEmpty {
            union.append(RadioGenre(name: "More genres", shoutcastGenre: nil,
                                    tags: [], subgenres: leftovers))
        }
        return union
    }
}
