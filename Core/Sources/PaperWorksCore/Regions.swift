import Foundation

/// A country, and within Canada a province: what decides whose rules a plan follows.
public struct Where: Equatable, Sendable {
    public var country: String?
    public var province: String?
    public init(country: String? = nil, province: String? = nil) { self.country = country; self.province = province }
}

public struct Region: Equatable, Sendable {
    public var code: String
    public var name: String
}

/// Countries with plans; after Canada and China, the ones with only visa plans.
public let COUNTRIES: [Region] = [
    Region(code: "CA", name: "Canada"),
    Region(code: "CN", name: "China"),
    Region(code: "US", name: "United States"),
    Region(code: "PH", name: "Philippines"),
    Region(code: "JP", name: "Japan"),
    Region(code: "GB", name: "United Kingdom"),
    Region(code: "SCHENGEN", name: "Schengen area (Europe)"),
]

/// One short-stay visa covers them all; a plan with country SCHENGEN fits any of them.
private let SCHENGEN: Set<String> = [
    "AT", "BE", "BG", "HR", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IS", "IT", "LV", "LI", "LT",
    "LU", "MT", "NL", "NO", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "CH",
]

public let PROVINCES: [Region] = [
    Region(code: "AB", name: "Alberta"),
    Region(code: "BC", name: "British Columbia"),
    Region(code: "MB", name: "Manitoba"),
    Region(code: "NB", name: "New Brunswick"),
    Region(code: "NL", name: "Newfoundland and Labrador"),
    Region(code: "NS", name: "Nova Scotia"),
    Region(code: "NT", name: "Northwest Territories"),
    Region(code: "NU", name: "Nunavut"),
    Region(code: "ON", name: "Ontario"),
    Region(code: "PE", name: "Prince Edward Island"),
    Region(code: "QC", name: "Quebec"),
    Region(code: "SK", name: "Saskatchewan"),
    Region(code: "YT", name: "Yukon"),
]

/// Last part of a place label -> ISO code, as the city list names countries. Ordered: first match names a code.
private let COUNTRY_NAMES: [(name: String, code: String)] = [
    "canada": "CA",
    "china": "CN",
    "united states": "US",
    "philippines": "PH",
    "japan": "JP",
    "united kingdom": "GB",
    "austria": "AT",
    "belgium": "BE",
    "bulgaria": "BG",
    "croatia": "HR",
    "czechia": "CZ",
    "denmark": "DK",
    "estonia": "EE",
    "finland": "FI",
    "france": "FR",
    "germany": "DE",
    "greece": "GR",
    "hungary": "HU",
    "iceland": "IS",
    "italy": "IT",
    "latvia": "LV",
    "liechtenstein": "LI",
    "lithuania": "LT",
    "luxembourg": "LU",
    "malta": "MT",
    "the netherlands": "NL",
    "netherlands": "NL",
    "norway": "NO",
    "poland": "PL",
    "portugal": "PT",
    "romania": "RO",
    "slovakia": "SK",
    "slovenia": "SI",
    "spain": "ES",
    "sweden": "SE",
    "switzerland": "CH",
].map { (name: $0.0, code: $0.1) }

private func countryCode(_ name: String) -> String? { COUNTRY_NAMES.first { $0.name == name }?.code }

public func provinceName(_ code: String?) -> String? { PROVINCES.first { $0.code == code }?.name }

public func countryName(_ code: String?) -> String? {
    if let n = COUNTRIES.first(where: { $0.code == code })?.name { return n }
    if let n = COUNTRY_NAMES.first(where: { $0.code == code })?.name { return n.capitalized }
    return code
}

/// "British Columbia" or "China".
public func whereName(_ w: Where) -> String? { provinceName(w.province) ?? countryName(w.country) }

/// Whose rules a plan carries: "Ontario", "China".
public func rulesName(_ pb: Playbook) -> String? { provinceName(pb.province) ?? countryName(pb.country) }

private func hasCJK(_ s: String) -> Bool { s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }

/// "Vancouver, British Columbia, Canada" -> CA/BC. A place typed in Chinese with no country is taken as China.
public func whereOf(_ location: String?) -> Where {
    guard let location, !location.isEmpty else { return Where() }
    let parts = location.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    let country = countryCode(parts.last ?? "") ?? (hasCJK(location) ? "CN" : nil)
    let province = country == "CA" ? PROVINCES.first { parts.contains($0.name.lowercased()) }?.code : nil
    return Where(country: country, province: province)
}

public func provinceOf(_ location: String?) -> String? { whereOf(location).province }

/// Dates that say where someone lives; a wedding or a trip abroad doesn't.
private let RESIDENCE_KINDS: Set<String> = ["born", "migrated", "moved-city", "home-bought"]

/// The latest date so far that says where they live and has a known place.
public func residenceOf(_ anchors: [Anchor], _ now: CivilDate) -> Anchor? {
    anchors
        .filter { $0.date <= now && RESIDENCE_KINDS.contains($0.kind) && whereOf($0.location).country != nil }
        .sorted { $0.date > $1.date }
        .first
}

/// Where they last moved to (or were born), from the places on their events.
public func livesIn(_ anchors: [Anchor], _ now: CivilDate) -> Where { whereOf(residenceOf(anchors, now)?.location) }

private func sameCountry(_ plan: String, _ place: String) -> Bool { plan == place || (plan == "SCHENGEN" && SCHENGEN.contains(place)) }

/// A plan fits unless its country or province is known to differ.
public func fits(_ pb: Playbook, _ w: Where) -> Bool {
    let c: Bool = { guard let pc = pb.country, let wc = w.country else { return true }; return sameCountry(pc, wc) }()
    let p: Bool = { guard let pp = pb.province, let wp = w.province else { return true }; return pp == wp }()
    return c && p
}

/// The same life stage for somewhere else, if one ships.
public func twinFor(_ pb: Playbook, _ w: Where, _ all: [Playbook]) -> Playbook? {
    guard let family = pb.family, let country = w.country, !fits(pb, w) else { return nil }
    let candidates = all.filter { $0.family == family && $0.country == country && fits($0, w) }
    return candidates.first { $0.province == w.province } ?? candidates.first
}

/// Whose rules a plan on this date follows. A wedding follows where it happens; a Born date follows where they live now.
public func whereAt(kind: String?, location: String?, _ lives: Where) -> Where {
    guard let kind else { return lives }
    let here = whereOf(location)
    if kind == "born" { return lives.country != nil ? lives : here }
    if here.country == nil { return lives }
    if here.province != nil || here.country != lives.country { return here }
    return Where(country: here.country, province: lives.province)
}

public func whereAt(_ anchor: Anchor?, _ lives: Where) -> Where { whereAt(kind: anchor?.kind, location: anchor?.location, lives) }

/// Why: "lives in British Columbia", "Married in Ontario", "lives in China".
public func whereWhy(_ anchor: Anchor?, _ lives: Where) -> String { whereWhy(kind: anchor?.kind, label: anchor?.label, location: anchor?.location, lives) }

public func whereWhy(kind: String?, label: String?, location: String?, _ lives: Where) -> String {
    let at = whereAt(kind: kind, location: location, lives)
    let here = whereOf(location)
    let name = whereName(at) ?? ""
    if let kind, let label, kind != "born", here.country != nil, here.country == at.country { return "\(label) in \(name)" }
    return "lives in \(name)"
}

/// The event that decided where a plan's date counts: the date's own place, or else the latest move.
public func decidedBy(_ anchor: Anchor?, _ anchors: [Anchor], _ now: CivilDate) -> Anchor? {
    if let anchor, anchor.kind != "born", whereOf(anchor.location).country != nil { return anchor }
    if let r = residenceOf(anchors, now) { return r }
    if let anchor, anchor.location != nil, !(anchor.location ?? "").isEmpty { return anchor }
    return nil
}

/// Whose passport they hold, as far as the app can tell: the country they were born in.
public func citizenOf(_ anchors: [Anchor]) -> String? { whereOf(anchors.first { $0.kind == "born" }?.location).country }

/// Where they lived just before an event: what a plan about leaving is matched against.
public func livedBefore(_ anchor: Anchor, _ anchors: [Anchor]) -> Where {
    livesIn(anchors.filter { $0.id != anchor.id && $0.date < anchor.date }, anchor.date)
}

/// A plan about leaving matches where they left; any other, where it counts.
public func whereFor(_ pb: Playbook, _ anchor: Anchor?, _ lives: Where, _ anchors: [Anchor]) -> Where {
    if pb.leaving == true, let anchor { return livedBefore(anchor, anchors) }
    return whereAt(anchor, lives)
}

/// Plans a date opens: those whose country/province fit where it counts, or for a plan about leaving,
/// where they lived before, and only when the event takes them elsewhere. On a trip, the user's own passport first.
public func plansFor(_ anchor: Anchor, _ lives: Where, _ playbooks: [Playbook], _ anchors: [Anchor] = []) -> [Playbook] {
    plansFor(kind: anchor.kind, location: anchor.location, anchor: anchor, lives, playbooks, anchors)
}

/// For an event not yet saved (no id/date).
public func plansFor(kind: String, location: String? = nil, anchor: Anchor? = nil, _ lives: Where, _ playbooks: [Playbook], _ anchors: [Anchor] = []) -> [Playbook] {
    let here = whereAt(kind: kind, location: location, lives)
    let before = anchor.map { livedBefore($0, anchors) } ?? lives
    let passport = citizenOf(anchors)
    let matched = playbooks.filter { pb in
        if opens(kind, pb) == nil { return false }
        if let c = pb.citizen, c == here.country { return false }
        if pb.leaving != true { return fits(pb, here) }
        return before.country != nil && fits(pb, before) && here.country != before.country
    }
    if kind != "trip" || passport == nil { return matched }
    func other(_ pb: Playbook) -> Int { if let c = pb.citizen, c != passport { return 1 }; return 0 }
    return matched.enumerated().sorted { a, b in
        other(a.element) != other(b.element) ? other(a.element) < other(b.element) : a.offset < b.offset
    }.map(\.element)
}
