import Foundation

public enum NameGender: String, Codable, Sendable { case f, m, u }
public enum NameSet: String, Codable, Sendable { case en, zh }
public enum GenderPick: String, Codable, Sendable { case f, m, all }

public struct BabyName: Codable, Equatable, Identifiable, Sendable {
    /// "en:Iris" · "zh:欣怡"
    public var id: String
    public var set: NameSet
    /// Latin spelling, or pinyin for Chinese names.
    public var name: String
    public var hanzi: String?
    public var gender: NameGender
    /// US rank over the last five years of SSA counts; nil when outside it.
    public var rank: Int?
    public var peak: Int?
    public var origin: String?
    public var language: String?
    public var meaning: String
    public var tags: [String]
    /// Where a Chinese name comes from: a poem line, idiom, solar term or person.
    public var source: String?

    public init(id: String, set: NameSet, name: String, hanzi: String? = nil, gender: NameGender, rank: Int? = nil,
                peak: Int? = nil, origin: String? = nil, language: String? = nil, meaning: String, tags: [String], source: String? = nil) {
        self.id = id; self.set = set; self.name = name; self.hanzi = hanzi; self.gender = gender; self.rank = rank
        self.peak = peak; self.origin = origin; self.language = language; self.meaning = meaning; self.tags = tags
        self.source = source
    }
}

public struct NamePrefs: Codable, Equatable, Sendable {
    public var set: NameSet
    public var gender: GenderPick
    /// Within a group (tags incl. popular/rare, origins, letters) any one is enough; groups narrow each other.
    public var tags: [String]
    /// Name origin or language; a name fits when it is any one of these. Empty means any.
    public var origins: [String]
    /// First letters (A-Z); a name fits when its initial is any one of these. Empty means any.
    public var initials: [String]
    public init(set: NameSet = .en, gender: GenderPick = .all, tags: [String] = [], origins: [String] = [], initials: [String] = []) {
        self.set = set; self.gender = gender; self.tags = tags; self.origins = origins; self.initials = initials
    }
}

public struct NameDecision: Codable, Equatable, Sendable {
    public var id: String
    public var liked: Bool
    /// Empty when the decision predates history.
    public var on: CivilDate
    public init(id: String, liked: Bool, on: CivilDate) { self.id = id; self.liked = liked; self.on = on }
}

public struct NameState: Codable, Equatable, Sendable {
    public var set: NameSet
    public var gender: GenderPick
    public var tags: [String]
    public var origins: [String]
    public var initials: [String]
    public var surname: String
    /// Family name in characters, shown on Chinese cards.
    public var surnameZh: String
    public var liked: [String]
    public var passed: [String]
    /// Oldest first.
    public var history: [NameDecision]
    /// Names typed in by the user, ids "custom:…"; never in the deck.
    public var custom: [BabyName]
    /// Fixes the shuffle, so the deck keeps its order between launches.
    public var seed: Int
    public init(set: NameSet = .en, gender: GenderPick = .all, tags: [String] = [], origins: [String] = [], initials: [String] = [], surname: String = "", surnameZh: String = "",
                liked: [String] = [], passed: [String] = [], history: [NameDecision] = [], custom: [BabyName] = [], seed: Int = 1) {
        self.set = set; self.gender = gender; self.tags = tags; self.origins = origins; self.initials = initials; self.surname = surname; self.surnameZh = surnameZh
        self.liked = liked; self.passed = passed; self.history = history; self.custom = custom; self.seed = seed
    }
    private enum Keys: String, CodingKey { case set, gender, tags, origins, initials, surname, surnameZh, liked, passed, history, custom, seed }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        set = try c.decode(NameSet.self, forKey: .set)
        gender = try c.decode(GenderPick.self, forKey: .gender)
        tags = try c.decode([String].self, forKey: .tags)
        origins = try c.decodeIfPresent([String].self, forKey: .origins) ?? []
        initials = try c.decodeIfPresent([String].self, forKey: .initials) ?? []
        surname = try c.decode(String.self, forKey: .surname)
        surnameZh = try c.decodeIfPresent(String.self, forKey: .surnameZh) ?? ""
        liked = try c.decode([String].self, forKey: .liked)
        passed = try c.decode([String].self, forKey: .passed)
        history = try c.decodeIfPresent([NameDecision].self, forKey: .history) ?? []
        custom = try c.decodeIfPresent([BabyName].self, forKey: .custom) ?? []
        seed = try c.decode(Int.self, forKey: .seed)
    }
    public var prefs: NamePrefs { NamePrefs(set: set, gender: gender, tags: tags, origins: origins, initials: initials) }
}

public let DEFAULT_NAMES = NameState()
public let POPULAR_RANK = 200
public let RARE_RANK = 2000
/// Latest year in the SSA counts the ranks come from.
public let NAMES_YEAR = 2025

public func matches(_ n: BabyName, _ prefs: NamePrefs) -> Bool {
    if n.set != prefs.set { return false }
    if prefs.gender != .all && n.gender.rawValue != prefs.gender.rawValue && n.gender != .u { return false }
    if !prefs.origins.isEmpty && !(n.origin.map(prefs.origins.contains) ?? false) { return false }
    if !prefs.initials.isEmpty && !prefs.initials.contains(nameInitial(n)) { return false }
    if prefs.tags.isEmpty { return true }
    return prefs.tags.contains { tag in
        switch tag {
        case "popular" where n.set == .en: n.rank.map { $0 <= POPULAR_RANK } ?? false
        case "rare" where n.set == .en: n.rank.map { $0 > RARE_RANK } ?? true
        case "rare": false
        default: n.tags.contains(tag)
        }
    }
}

/// First letter, uppercased, accents folded; Chinese names use their pinyin ("Ǎn" → "A").
public func nameInitial(_ n: BabyName) -> String {
    guard let c = n.name.folding(options: .diacriticInsensitive, locale: nil).first(where: \.isLetter) else { return "" }
    return String(c).uppercased()
}

/// Names per initial among those fitting the set and gender.
public func initialCounts(_ all: [BabyName], set: NameSet, gender: GenderPick) -> [String: Int] {
    var counts: [String: Int] = [:]
    for n in all where matches(n, NamePrefs(set: set, gender: gender)) { counts[nameInitial(n), default: 0] += 1 }
    return counts
}

/// Most common origins among the English names, most first.
public func topOrigins(_ all: [BabyName], limit: Int) -> [String] {
    var counts: [String: Int] = [:]
    for n in all where n.set == .en { if let o = n.origin, !o.isEmpty { counts[o, default: 0] += 1 } }
    return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit).map(\.key)
}

/// "Iris Xie" · "谢欣怡"
public func fullName(_ n: BabyName, _ s: NameState) -> String {
    if let h = n.hanzi { return s.surnameZh + h }
    return [n.name, s.surname].filter { !$0.isEmpty }.joined(separator: " ")
}

public func matches(_ n: BabyName, _ state: NameState) -> Bool { matches(n, state.prefs) }

/// Stable pseudo-random order: the same seed gives the same deck.
private func score(_ id: String, _ seed: Int) -> UInt32 {
    var h: UInt32 = 2166136261 ^ UInt32(truncatingIfNeeded: seed)
    for u in id.utf16 { h = (h ^ UInt32(u)) &* 16777619 }
    return h
}

/// Names still to show for these prefs, in deck order.
/// A spelling variant shows on its root's card, unless the root doesn't fit the filters.
func hiddenVariant(_ n: BabyName, _ state: NameState) -> Bool {
    guard let root = NAME_ROOT[n.id].flatMap({ NAMES_BY_ID[$0] }) else { return false }
    return matches(root, state)
}

public func deck(_ all: [BabyName], _ state: NameState) -> [BabyName] {
    let seen = Set((state.liked + state.passed).map(nameGroup))
    return all.enumerated()
        .filter { matches($0.element, state) && !seen.contains(nameGroup($0.element.id)) && !hiddenVariant($0.element, state) }
        .map { (n: $0.element, s: score($0.element.id, state.seed), i: $0.offset) }
        .sorted { $0.s != $1.s ? $0.s < $1.s : $0.i < $1.i }
        .map(\.n)
}

/// How many names fit the prefs at all, seen or not.
public func fitting(_ all: [BabyName], _ prefs: NamePrefs) -> Int { all.filter { matches($0, prefs) }.count }
public func fitting(_ all: [BabyName], _ state: NameState) -> Int { fitting(all, state.prefs) }

/// Puts names decided before history existed at the start, undated.
private func backfilled(_ s: NameState) -> NameState {
    var s = s
    let known = Set(s.history.map(\.id))
    var old: [NameDecision] = []
    for id in s.passed + s.liked where !known.contains(id) && !old.contains(where: { $0.id == id }) {
        old.append(NameDecision(id: id, liked: s.liked.contains(id), on: ""))
    }
    s.history = old + s.history
    return s
}

private func record(_ s: NameState, _ id: String, liked: Bool, _ on: CivilDate) -> NameState {
    var s = backfilled(s)
    s.history.removeAll { $0.id == id }
    s.history.append(NameDecision(id: id, liked: liked, on: on))
    return s
}

public func like(_ s: NameState, _ id: String, on: CivilDate = today()) -> NameState {
    var s = s
    if !s.liked.contains(id) { s.liked.append(id) }
    s.passed.removeAll { $0 == id }
    return record(s, id, liked: true, on)
}

public func pass(_ s: NameState, _ id: String, on: CivilDate = today()) -> NameState {
    var s = s
    if !s.passed.contains(id) { s.passed.append(id) }
    s.liked.removeAll { $0 == id }
    return record(s, id, liked: false, on)
}

/// Back into the deck.
public func forget(_ s: NameState, _ id: String) -> NameState {
    var s = backfilled(s)
    s.liked.removeAll { $0 == id }
    s.passed.removeAll { $0 == id }
    s.history.removeAll { $0.id == id }
    s.custom.removeAll { $0.id == id }
    return s
}

public func unlike(_ s: NameState, _ id: String) -> NameState { forget(s, id) }

/// Like becomes skip and the other way round, dated as a new decision.
public func flip(_ s: NameState, _ id: String, on: CivilDate = today()) -> NameState {
    if s.liked.contains(id) { return pass(s, id, on: on) }
    if s.passed.contains(id) { return like(s, id, on: on) }
    return s
}

/// Every decided name, newest first; names from before history come last, undated.
public func decisions(_ s: NameState) -> [NameDecision] { backfilled(s).history.reversed() }

/// "Today" · "Yesterday" · "3 days ago" · "Earlier" when undated.
public func relativeDay(_ on: CivilDate, now: CivilDate = today()) -> String {
    if on.isEmpty { return "Earlier" }
    switch diffDays(on, now) {
    case ...0: return "Today"
    case 1: return "Yesterday"
    case let d: return "\(d) days ago"
    }
}

/// Brings back the passed names that fit the prefs, reshuffled.
public func reshuffle(_ all: [BabyName], _ s: NameState) -> NameState {
    let fit = Set(all.filter { matches($0, s) }.map(\.id))
    var s = backfilled(s)
    s.passed.removeAll { fit.contains($0) }
    s.history.removeAll { fit.contains($0.id) && !$0.liked }
    s.seed += 1
    return s
}

/// Source up to the quoted line: "曹植《洛神赋》：翩若惊鸿。" → "曹植《洛神赋》"; other sources unchanged.
public func sourceShort(_ source: String) -> String {
    guard let r = source.range(of: "》：") else { return source }
    return String(source[..<source.index(after: r.lowerBound)])
}

/// The quoted line of a "作者《篇名》：句子。" source, without its final 。
public func sourceQuote(_ source: String) -> String? {
    guard let r = source.range(of: "》：") else { return nil }
    let q = source[r.upperBound...].trimmingCharacters(in: .whitespaces)
    let line = q.hasSuffix("。") ? String(q.dropLast()) : q
    return line.isEmpty ? nil : line
}

/// "#12 in the US" · "Rare in the US"
public func rankLabel(_ n: BabyName) -> String? {
    if n.set != .en { return nil }
    guard let r = n.rank, r <= RARE_RANK else { return "Rare in the US" }
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_US")
    f.numberStyle = .decimal
    return "#\(f.string(from: NSNumber(value: r)) ?? String(r)) in the US"
}

// Rows: en [name, gender, rank|null, peak, origin, language, meaning, tags]; zh [pinyin, hanzi, gender, meaning, tags, source?].
private enum Cell: Decodable {
    case s(String), i(Int), null
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let i = try? c.decode(Int.self) { self = .i(i) }
        else { self = .s(try c.decode(String.self)) }
    }
    var str: String { if case .s(let s) = self { return s }; return "" }
    var int: Int? { if case .i(let i) = self { return i }; return nil }
}

private func words(_ s: String) -> [String] { s.isEmpty ? [] : s.split(separator: " ").map(String.init) }

private func rows(_ name: String) -> [[Cell]] {
    do { return try JSONDecoder().decode([[Cell]].self, from: bundledResource(name)) }
    catch { fatalError("\(name).json: \(error)") }
}

public let NAMES: [BabyName] = {
    let en = rows("names-en").map { r in
        BabyName(id: "en:\(r[0].str)", set: .en, name: r[0].str, gender: NameGender(rawValue: r[1].str) ?? .u,
                 rank: r[2].int, peak: r[3].int, origin: r[4].str, language: r[5].str, meaning: r[6].str, tags: words(r[7].str))
    }
    let zh = rows("names-zh").map { r in
        BabyName(id: "zh:\(r[1].str)", set: .zh, name: r[0].str, hanzi: r[1].str, gender: NameGender(rawValue: r[2].str) ?? .u,
                 origin: "Chinese", language: "Chinese", meaning: r[3].str, tags: words(r[4].str),
                 source: r.count > 5 && !r[5].str.isEmpty ? r[5].str : nil)
    }
    return en + zh
}()

public let NAMES_BY_ID: [String: BabyName] = Dictionary(NAMES.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

// MARK: - Spelling variants

/// Rough sound key: "Deborah"/"Debora", "Corbin"/"Korbin" match; "Anna"/"Hannah", "Mary"/"Marie" don't.
func soundKey(_ name: String) -> String {
    var s = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    for (a, b) in [("ph", "f"), ("ck", "c"), ("k", "c"), ("q", "c"), ("y", "i")] {
        s = s.replacingOccurrences(of: a, with: b)
    }
    if s.count > 3, s.hasSuffix("h"), let v = s.dropLast().last, "aeiou".contains(v) { s.removeLast() }
    var out = ""
    for ch in s where ch.isLetter && ch != out.last { out.append(ch) }
    while out.count > 3, out.last == "e", let prev = out.dropLast().last, !"aeiou".contains(prev) { out.removeLast() }
    return out
}

private func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    var row = Array(0...b.count)
    for i in 1...max(a.count, 1) where !a.isEmpty {
        var prev = row[0]; row[0] = i
        for j in 1...max(b.count, 1) where !b.isEmpty {
            let cur = row[j]
            row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
            prev = cur
        }
    }
    return a.isEmpty ? b.count : row[b.count]
}

private func meaningWords(_ meaning: String) -> Set<String> {
    let core = meaning.components(separatedBy: " · ").last ?? meaning
    if core.hasPrefix("Form of") || core.hasPrefix("Short for") || core.hasPrefix("Modern") || core.hasPrefix("Origin")
        || core.hasPrefix("Blend") { return [] }
    let stop: Set<String> = ["a", "an", "the", "of", "and", "or", "to", "in", "is", "flower", "plant", "tree", "one", "who"]
    return Set(core.lowercased().split { !$0.isLetter }.map(String.init).filter { !stop.contains($0) })
}

/// Name id → the most popular name of its family ("en:Rosie" → "en:Rose", "en:Sofia" → "en:Sophia").
/// Same gender and opening sound, plus the same sound key, the same meaning, or a "Form of"/"Short for" link.
public let NAME_ROOT: [String: String] = {
    let en = NAMES.filter { $0.set == .en }
    var parent = Dictionary(uniqueKeysWithValues: en.map { ($0.id, $0.id) })
    func find(_ x: String) -> String { var x = x; while parent[x]! != x { x = parent[x]! }; return x }
    func union(_ a: String, _ b: String) { let (ra, rb) = (find(a), find(b)); if ra != rb { parent[ra] = rb } }
    let key = Dictionary(uniqueKeysWithValues: en.map { ($0.id, soundKey($0.name)) })
    func opening(_ id: String) -> String { String(key[id]!.replacingOccurrences(of: "h", with: "").prefix(3)) }
    let words = Dictionary(uniqueKeysWithValues: en.map { ($0.id, meaningWords($0.meaning)) })

    for bucket in Dictionary(grouping: en, by: { "\(opening($0.id))|\($0.gender.rawValue)" }).values where bucket.count > 1 {
        for (i, a) in bucket.enumerated() {
            for b in bucket[(i + 1)...] {
                let (wa, wb) = (words[a.id]!, words[b.id]!)
                let sameMeaning = !wa.isEmpty && !wb.isEmpty && (wa.isSubset(of: wb) || wb.isSubset(of: wa))
                if key[a.id] == key[b.id] || sameMeaning { union(a.id, b.id) }
            }
        }
    }
    for n in en {
        for prefix in ["Form of ", "Short for "] where n.meaning.hasPrefix(prefix) {
            let rootName = n.meaning.dropFirst(prefix.count).prefix { $0.isLetter }
            guard let root = NAMES_BY_ID["en:\(rootName)"], root.id != n.id, root.gender == n.gender,
                  opening(root.id).prefix(2) == opening(n.id).prefix(2) else { continue }
            union(n.id, root.id)
        }
    }
    var roots: [String: String] = [:]
    for g in Dictionary(grouping: en, by: { find($0.id) }).values where g.count > 1 {
        let top = g.min { ($0.rank ?? .max, $0.name) < ($1.rank ?? .max, $1.name) }!
        for n in g where n.id != top.id { roots[n.id] = top.id }
    }
    return roots
}()

/// The id that stands for a name and all its spellings.
public func nameGroup(_ id: String) -> String { NAME_ROOT[id] ?? id }

/// Root id → its other spellings, most popular first.
public let NAME_VARIANTS: [String: [BabyName]] = Dictionary(grouping: NAME_ROOT.keys.compactMap { NAMES_BY_ID[$0] }) {
    NAME_ROOT[$0.id]!
}.mapValues { $0.sorted { ($0.rank ?? .max) < ($1.rank ?? .max) } }

public let CUSTOM_TAG = "your name"

/// Bundled or custom name.
public func nameById(_ id: String, _ s: NameState) -> BabyName? {
    NAMES_BY_ID[id] ?? s.custom.first { $0.id == id }
}

/// Bundled name with the same spelling (case-insensitive) or characters, in that set.
public func bundledMatch(_ set: NameSet, name: String, hanzi: String, in names: [BabyName] = NAMES) -> BabyName? {
    let n = name.trimmingCharacters(in: .whitespaces), h = hanzi.trimmingCharacters(in: .whitespaces)
    if set == .zh { return h.isEmpty ? nil : names.first { $0.set == .zh && $0.hanzi == h } }
    return n.isEmpty ? nil : names.first { $0.set == .en && $0.name.caseInsensitiveCompare(n) == .orderedSame }
}

/// Likes the bundled twin if there is one, else adds a custom name; nil when the input is empty.
public func addName(_ s: NameState, set: NameSet, name: String, hanzi: String = "", gender: NameGender,
                    meaning: String = "", origin: String = "", on: CivilDate = today()) -> NameState? {
    let n = name.trimmingCharacters(in: .whitespaces), h = hanzi.trimmingCharacters(in: .whitespaces)
    if let m = bundledMatch(set, name: n, hanzi: h) { return like(s, m.id, on: on) }
    let key = set == .zh ? h : n
    guard !key.isEmpty else { return nil }
    let id = "custom:\(set.rawValue):\(key.lowercased())"
    var s = s
    if !s.custom.contains(where: { $0.id == id }) {
        let o = origin.trimmingCharacters(in: .whitespaces)
        s.custom.append(BabyName(id: id, set: set, name: n, hanzi: set == .zh ? h : nil, gender: gender,
                                 origin: o.isEmpty ? nil : o, meaning: meaning.trimmingCharacters(in: .whitespaces), tags: [CUSTOM_TAG]))
    }
    return like(s, id, on: on)
}
