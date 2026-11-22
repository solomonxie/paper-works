import Foundation
import Testing
@testable import PaperWorksCore

@Test func namesSurviveSettingsRoundTrip() throws {
    var s = DEFAULT_SETTINGS
    var n = DEFAULT_NAMES
    n = pass(like(n, "en:Iris", on: "2026-11-21"), "en:Noah", on: "2026-11-21")
    n.surnameZh = "谢"
    s.names = n
    let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
    #expect(back.names == n)
}

@Test func spellingVariantsShareOneCard() {
    #expect(NAME_ROOT["en:Hanna"] == "en:Hannah")
    #expect(NAME_ROOT["en:Shilo"] == "en:Shiloh")
    #expect(NAME_ROOT["en:Dario"] == nil)
    #expect(NAME_ROOT["en:Musa"] == nil)
    var s = DEFAULT_NAMES; s.gender = .f
    let ids = Set(deck(NAMES, s).map(\.id))
    #expect(ids.contains("en:Hannah") && !ids.contains("en:Hanna"))
}

@Test func allTagsIncludingPopularityAreOneUnionGroup() {
    let iris = BabyName(id: "en:Iris", set: .en, name: "Iris", gender: .f, rank: 150, origin: "Greek", meaning: "", tags: ["flower"])
    let ruth = BabyName(id: "en:Ruth", set: .en, name: "Ruth", gender: .f, rank: 409, origin: "Hebrew", meaning: "", tags: ["bible"])
    var s = DEFAULT_NAMES; s.tags = ["bible", "flower"]
    #expect(matches(iris, s) && matches(ruth, s))
    s.tags = ["bible", "popular"]
    #expect(matches(iris, s) && matches(ruth, s))
    s.tags = ["rare", "bible"]
    #expect(!matches(iris, s) && matches(ruth, s))
    s.tags = ["bible", "flower"]; s.origins = ["Hebrew"]
    #expect(!matches(iris, s) && matches(ruth, s))
}

@Test func namesGroupIntoFamilies() {
    #expect(nameGroup("en:Rosie") == nameGroup("en:Rose"))
    #expect(nameGroup("en:Sofia") == nameGroup("en:Sophia"))
    #expect(nameGroup("en:Kristina") == nameGroup("en:Christina"))
    #expect(nameGroup("en:Debora") == nameGroup("en:Deborah"))
    #expect(nameGroup("en:Hadassa") == nameGroup("en:Hadassah"))
    #expect(nameGroup("en:Rebekah") == nameGroup("en:Rebecca"))
    #expect(nameGroup("en:Brian") != nameGroup("en:Brianna"))
    #expect(nameGroup("en:Salome") != nameGroup("en:Shalom"))
}

@Test func decidingOneSpellingHidesTheOthers() {
    var s = DEFAULT_NAMES; s.gender = .f
    s = pass(s, "en:Debora")
    let ids = Set(deck(NAMES, s).map(\.id))
    #expect(!ids.contains("en:Deborah") && !ids.contains("en:Debora"))
}

@Test func unionWithinGroupsIntersectionAcross() {
    var s = DEFAULT_NAMES; s.gender = .f
    s.origins = ["Hebrew", "Greek"]; s.initials = ["A", "B"]
    let names = deck(NAMES, s)
    #expect(!names.isEmpty)
    #expect(names.allSatisfy { ["Hebrew", "Greek"].contains($0.origin ?? "") && ["A", "B"].contains(nameInitial($0)) })
    #expect(Set(names.map { $0.origin ?? "" }) == ["Hebrew", "Greek"])
    #expect(Set(names.map(nameInitial)) == ["A", "B"])
}
