import Foundation
import Testing
@testable import PaperWorksCore

@Test func toolPlansSurviveSettingsRoundTrip() throws {
    var s = DEFAULT_SETTINGS
    s.toolPlans = [ToolPlan(id: "t1", kind: .babyNames, personId: "me", anchorId: "a1", addedOn: "2026-11-21")]
    let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
    #expect(back.toolPlans == s.toolPlans)
}

@Test func oldSettingsDecodeWithoutToolPlans() throws {
    let back = try JSONDecoder().decode(Settings.self, from: Data(#"{"leadDays":7}"#.utf8))
    #expect(back.toolPlans.isEmpty && back.leadDays == 7)
}

@Test func babyNamesSuggestedByBabyEventsOnly() {
    #expect(toolPlanKinds(suggestedBy: "baby-due").map(\.kind) == [.babyNames])
    #expect(toolPlanKinds(suggestedBy: "child-born").map(\.kind) == [.babyNames])
    #expect(toolPlanKinds(suggestedBy: "born").isEmpty)
}

@Test func oldPlanDecodesWithoutNamesOrTitle() throws {
    let tp = try JSONDecoder().decode(ToolPlan.self, from: Data(#"{"id":"t","kind":"babyNames","addedOn":"2026-11-21"}"#.utf8))
    #expect(tp.names == nil && tp.title == nil)
}

@Test func migrationMovesGlobalNamesIntoFirstPlan() {
    var s = DEFAULT_SETTINGS
    s.names = NameState(liked: ["a"], seed: 7)
    s.toolPlans = [ToolPlan(id: "p1", kind: .babyNames, addedOn: "2026-11-21"), ToolPlan(id: "p2", kind: .babyNames, addedOn: "2026-11-21")]
    let out = migrateNames(s, owner: "me", newId: { "new" }, today: "2026-11-21")
    #expect(out.names == nil && out.toolPlans[0].names?.liked == ["a"] && out.toolPlans[1].names == nil)
    #expect(migrateNames(out, owner: "me", newId: { "x" }, today: "2026-11-21") == out)
}

@Test func migrationCreatesPlanOnlyWhenDecisionsExist() {
    var s = DEFAULT_SETTINGS
    s.names = NameState(liked: ["a"])
    let out = migrateNames(s, owner: "me", newId: { "new" }, today: "2026-11-21")
    #expect(out.toolPlans.map(\.id) == ["new"] && out.toolPlans[0].names?.liked == ["a"] && out.toolPlans[0].personId == "me")
    s.names = NameState()
    #expect(migrateNames(s, owner: "me", newId: { "new" }, today: "2026-11-21").toolPlans.isEmpty)
}

@Test func twoPlansKeepIndependentNamesAndTitles() throws {
    var a = ToolPlan(id: "1", kind: .babyNames, addedOn: "2026-11-21", names: NameState(liked: ["x"]))
    let b = ToolPlan(id: "2", kind: .babyNames, addedOn: "2026-11-21", names: NameState(liked: ["y"]))
    a.names?.liked.append("z")
    #expect(b.names?.liked == ["y"] && a.names?.liked == ["x", "z"])
    #expect(toolPlanTitle(a, in: [a, b], anchors: []) == "Baby names")
    #expect(toolPlanTitle(b, in: [a, b], anchors: []) == "Baby names (2)")
    let back = try JSONDecoder().decode([ToolPlan].self, from: JSONEncoder().encode([a, b]))
    #expect(back == [a, b])
}
