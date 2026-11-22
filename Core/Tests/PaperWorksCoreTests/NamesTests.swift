import Foundation
import Testing
@testable import PaperWorksCore

private func n(_ name: String, gender: NameGender = .f, rank: Int? = nil, tags: [String] = []) -> BabyName {
    BabyName(id: "en:\(name)", set: .en, name: name, gender: gender, rank: rank, meaning: "", tags: tags)
}

private let ALL: [BabyName] = [
    n("Iris", rank: 150, tags: ["flower"]),
    n("Hannah", rank: 40, tags: ["bible"]),
    n("Noah", gender: .m, rank: 2, tags: ["bible"]),
    n("Riley", gender: .u, rank: 300),
    n("Zina"),
    BabyName(id: "zh:欣怡", set: .zh, name: "Xinyi", hanzi: "欣怡", gender: .f, meaning: "", tags: []),
]

@Suite struct NamesTests {
    @Test func filters() {
        var girls = DEFAULT_NAMES; girls.gender = .f
        #expect(ALL.filter { matches($0, girls) }.map(\.name) == ["Iris", "Hannah", "Riley", "Zina"])
        var bible = girls; bible.tags = ["bible"]
        #expect(ALL.filter { matches($0, bible) }.map(\.name) == ["Hannah"])
        var zh = DEFAULT_NAMES; zh.set = .zh
        #expect(ALL.filter { matches($0, zh) }.map(\.id) == ["zh:欣怡"])
    }

    @Test func popularAndRare() {
        var s = DEFAULT_NAMES; s.tags = ["popular"]
        #expect(ALL.filter { matches($0, s) }.map(\.name) == ["Iris", "Hannah", "Noah"])
        s.tags = ["rare"]
        #expect(ALL.filter { matches($0, s) }.map(\.name) == ["Zina"])
    }

    @Test func chineseTagsAreOrdinary() {
        let zhNames = [BabyName(id: "zh:a", set: .zh, name: "A", hanzi: "甲", gender: .u, meaning: "", tags: ["popular", "poetry"]),
                       BabyName(id: "zh:b", set: .zh, name: "B", hanzi: "乙", gender: .u, meaning: "", tags: ["poetry"])]
        var s = NameState(set: .zh, tags: ["popular"])
        #expect(zhNames.map { matches($0, s) } == [true, false])
        s.tags = ["rare"]
        #expect(zhNames.map { matches($0, s) } == [false, false])
        s.tags = ["poetry"]
        #expect(zhNames.map { matches($0, s) } == [true, true])
    }

    @Test func sourceParts() throws {
        let src = "曹植《洛神赋》：翩若惊鸿，婉若游龙。"
        #expect(sourceShort(src) == "曹植《洛神赋》")
        #expect(sourceQuote(src) == "翩若惊鸿，婉若游龙")
        #expect(sourceShort("成语：宁静致远") == "成语：宁静致远")
        #expect(sourceQuote("成语：宁静致远") == nil)
        let b = BabyName(id: "x", set: .zh, name: "", gender: .u, meaning: "", tags: [], source: src)
        #expect(try JSONDecoder().decode(BabyName.self, from: JSONEncoder().encode(b)).source == src)
    }

    @Test func stableDeck() {
        let first = deck(ALL, DEFAULT_NAMES).map(\.id)
        #expect(deck(ALL, DEFAULT_NAMES).map(\.id) == first)
        #expect(first.count == 5)
        let s = pass(like(DEFAULT_NAMES, first[0]), first[1])
        #expect(deck(ALL, s).map(\.id) == Array(first.dropFirst(2)))
    }

    @Test func likeAndUnlike() {
        let s = like(pass(DEFAULT_NAMES, "en:Iris"), "en:Iris")
        #expect(s.liked == ["en:Iris"])
        #expect(s.passed == [])
        #expect(unlike(s, "en:Iris").liked == [])
    }

    @Test func historyOrderAndFlip() {
        var s = like(DEFAULT_NAMES, "en:Iris", on: "2026-01-01")
        s = pass(s, "en:Noah", on: "2026-01-02")
        s = flip(s, "en:Iris", on: "2026-01-03")
        #expect(decisions(s).map(\.id) == ["en:Iris", "en:Noah"])
        #expect(decisions(s)[0] == NameDecision(id: "en:Iris", liked: false, on: "2026-01-03"))
        #expect(s.liked == [] && s.passed == ["en:Noah", "en:Iris"])
        s = flip(s, "en:Iris", on: "2026-01-04")
        #expect(s.liked == ["en:Iris"] && s.passed == ["en:Noah"])
    }

    @Test func forgetReturnsToDeck() {
        let s = forget(like(DEFAULT_NAMES, "en:Iris"), "en:Iris")
        #expect(s.liked.isEmpty && s.history.isEmpty)
        #expect(deck(ALL, s).count == 5)
        #expect(unlike(like(DEFAULT_NAMES, "en:Iris"), "en:Iris").history.isEmpty)
    }

    @Test func oldStateWithoutHistory() throws {
        let json = #"{"set":"en","gender":"all","tags":[],"surname":"","liked":["en:Iris"],"passed":["en:Noah"],"seed":1}"#
        let s = try JSONDecoder().decode(NameState.self, from: Data(json.utf8))
        #expect(s.history == [])
        #expect(s.surnameZh == "")
        #expect(decisions(s).map(\.id) == ["en:Iris", "en:Noah"])
        #expect(decisions(s).allSatisfy { $0.on.isEmpty })
        let t = like(s, "en:Hannah", on: "2026-02-01")
        #expect(decisions(t).map(\.id) == ["en:Hannah", "en:Iris", "en:Noah"])
    }

    @Test func fullNames() {
        let s = NameState(surname: "Xie", surnameZh: "谢")
        #expect(fullName(ALL[0], s) == "Iris Xie")
        #expect(fullName(ALL[5], s) == "谢欣怡")
        #expect(fullName(ALL[0], DEFAULT_NAMES) == "Iris")
    }

    @Test func relativeDays() {
        #expect(relativeDay("2026-03-10", now: "2026-03-10") == "Today")
        #expect(relativeDay("2026-03-09", now: "2026-03-10") == "Yesterday")
        #expect(relativeDay("2026-03-05", now: "2026-03-10") == "5 days ago")
        #expect(relativeDay("", now: "2026-03-10") == "Earlier")
    }

    @Test func reshuffleKeepsLikes() {
        var s = DEFAULT_NAMES; s.gender = .m
        s = like(pass(pass(s, "en:Noah"), "en:Iris"), "en:Riley")
        let r = reshuffle(ALL, s)
        #expect(r.passed == ["en:Iris"])
        #expect(r.liked == ["en:Riley"])
        #expect(r.seed == s.seed + 1)
        #expect(fitting(ALL, s) == 2)
    }

    @Test func rankLabels() {
        #expect(rankLabel(ALL[0]) == "#150 in the US")
        #expect(rankLabel(ALL[4]) == "Rare in the US")
        #expect(rankLabel(ALL[5]) == nil)
    }

    @Test func bundledNames() {
        let en = NAMES.filter { $0.set == .en }, zh = NAMES.filter { $0.set == .zh }
        #expect(en.count > 4000)
        #expect(zh.count > 300)
        #expect(Set(NAMES.map(\.id)).count == NAMES.count)
        #expect(NAMES.allSatisfy { !$0.meaning.isEmpty })
        #expect(zh.allSatisfy { !($0.hanzi ?? "").isEmpty })
    }

    @Test func originFilter() throws {
        let greek = BabyName(id: "en:Iris", set: .en, name: "Iris", gender: .f, origin: "Greek", meaning: "", tags: ["flower"])
        let hebrew = BabyName(id: "en:Ruth", set: .en, name: "Ruth", gender: .f, origin: "Hebrew", meaning: "", tags: ["bible"])
        let none = BabyName(id: "en:X", set: .en, name: "X", gender: .f, meaning: "", tags: [])
        var s = DEFAULT_NAMES
        #expect([greek, hebrew, none].allSatisfy { matches($0, s) })
        s.origins = ["Greek"]
        #expect(matches(greek, s) && !matches(hebrew, s) && !matches(none, s))
        s.origins = ["Greek", "Hebrew"]; s.tags = ["bible"]
        #expect(!matches(greek, s) && matches(hebrew, s))
        #expect(topOrigins([greek, hebrew, hebrew], limit: 1) == ["Hebrew"])
    }

    @Test func initialFilter() throws {
        let en = [n("Élodie"), n("Iris"), n("Ivy")]
        let zh = [BabyName(id: "zh:子涵", set: .zh, name: "Zǐhán", hanzi: "子涵", gender: .m, meaning: "", tags: []),
                  BabyName(id: "zh:安", set: .zh, name: "Ān", hanzi: "安", gender: .m, meaning: "", tags: [])]
        #expect(en.map(nameInitial) == ["E", "I", "I"])
        #expect(zh.map(nameInitial) == ["Z", "A"])
        var s = DEFAULT_NAMES
        s.initials = ["I", "E"]
        #expect(en.allSatisfy { matches($0, s) })
        s.initials = ["I"]
        #expect(en.map { matches($0, s) } == [false, true, true])
        s.tags = ["bible"]
        #expect(!matches(en[1], s))
        s = NameState(set: .zh, initials: ["Z"])
        #expect(zh.map { matches($0, s) } == [true, false])
        #expect(initialCounts(en + zh, set: .zh, gender: .all) == ["Z": 1, "A": 1])
        #expect(initialCounts(en + zh, set: .en, gender: .all) == ["E": 1, "I": 2])
    }

    @Test func oldStateDecodesWithoutInitials() throws {
        let json = #"{"set":"en","gender":"all","tags":[],"surname":"","liked":[],"passed":[],"seed":1}"#
        #expect(try JSONDecoder().decode(NameState.self, from: Data(json.utf8)).initials.isEmpty)
    }

    @Test func oldStateDecodesWithoutOrigins() throws {
        let json = #"{"set":"en","gender":"all","tags":[],"surname":"","liked":[],"passed":[],"seed":1}"#
        let s = try JSONDecoder().decode(NameState.self, from: Data(json.utf8))
        #expect(s.origins.isEmpty)
    }

    @Test func customNames() throws {
        let s = try #require(addName(NameState(), set: .en, name: "Zyzzy", gender: .u, meaning: "Mine"))
        #expect(s.liked == ["custom:en:zyzzy"] && nameById("custom:en:zyzzy", s)?.meaning == "Mine")
        #expect(NAMES_BY_ID["custom:en:zyzzy"] == nil)
        let back = try JSONDecoder().decode(NameState.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        #expect(forget(s, "custom:en:zyzzy").custom.isEmpty)
        #expect(addName(NameState(), set: .en, name: "  ", gender: .f) == nil)
    }

    @Test func customMatchesBundled() throws {
        let s = try #require(addName(NameState(), set: .en, name: "iris", gender: .m))
        #expect(s.liked == ["en:Iris"] && s.custom.isEmpty)
    }
}
