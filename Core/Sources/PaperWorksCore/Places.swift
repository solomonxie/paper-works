import Foundation

public struct Place: Equatable, Sendable {
    public var name: String
    public var zh: String
    public var admin: String
    public var country: String
    /// 0 is the most populous.
    public var rank: Int
}

private struct Indexed {
    let place: Place
    let key: String
    let `where`: String
}

private func fold(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }

private let placeIndex: [Indexed] = {
    let regions = bundledRegions.split(separator: "\n", omittingEmptySubsequences: false).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    return bundledCities.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { rank, row in
        let c = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard c.count >= 2, let r = Int(c[1]), r < regions.count, regions[r].count >= 2 else { return nil }
        let p = Place(name: c[0], zh: c.count > 2 ? c[2] : "", admin: regions[r][0], country: regions[r][1], rank: rank)
        return Indexed(place: p, key: fold(p.name), where: fold("\(p.admin) \(p.country)"))
    }
}()

public func placeLabel(_ p: Place) -> String { placeLabel(name: p.name, admin: p.admin, country: p.country) }

public func placeLabel(name: String, admin: String, country: String) -> String {
    [name, admin != name ? admin : "", country].filter { !$0.isEmpty }.joined(separator: ", ")
}

/// The town alone, for tight rows: "Toronto" from "Toronto, Ontario, Canada".
public func placeShort(_ label: String) -> String {
    (label.split(separator: ",", omittingEmptySubsequences: false).first.map(String.init) ?? "").trimmingCharacters(in: .whitespaces)
}

/// Prefix matches first, then word starts, then anywhere; bigger places first, `near` (a country name) ahead.
/// "london, on" narrows by region or country after the comma.
public func searchPlaces(_ query: String, limit: Int = 8, near: String? = nil) -> [Place] {
    let pieces = query.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    let rawHead = pieces[0].trimmingCharacters(in: .whitespaces)
    let needle = fold(rawHead)
    let within = fold(pieces.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces))
    if needle.isEmpty { return [] }
    func away(_ p: Place) -> Int { if let near, p.country != near { return 1 }; return 0 }
    var scored: [(p: Place, score: Int)] = []
    for ix in placeIndex {
        if !within.isEmpty && !ix.where.contains(within) { continue }
        let zh = ix.place.zh
        var score = -1
        if ix.key.hasPrefix(needle) || (!zh.isEmpty && zh.hasPrefix(rawHead)) { score = 0 }
        else if ix.key.contains(" \(needle)") || ix.key.contains("-\(needle)") { score = 1 }
        else if ix.key.contains(needle) || (!zh.isEmpty && zh.contains(rawHead)) { score = 2 }
        if score >= 0 { scored.append((ix.place, score)) }
    }
    scored.sort { a, b in
        if a.score != b.score { return a.score < b.score }
        if away(a.p) != away(b.p) { return away(a.p) < away(b.p) }
        return a.p.rank < b.p.rank
    }
    return scored.prefix(limit).map(\.p)
}
