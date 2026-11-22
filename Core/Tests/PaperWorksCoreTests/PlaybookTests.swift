import Testing
@testable import PaperWorksCore

private typealias Obj = [String: Any]

private func stepObj(_ id: String, _ title: String, offset: Any = 0, duration: Any = 1, deps: [String]? = nil, extra: Obj = [:]) -> Obj {
    var o: Obj = ["id": id, "title": title, "offsetDays": offset, "durationDays": duration]
    if let deps { o["dependsOn"] = deps }
    return o.merging(extra) { $1 }
}

private var validSteps: [Obj] { [
    stepObj("a", "Book test", offset: -10, duration: 5, deps: []),
    stepObj("b", "Lodge EOI", offset: 0, duration: 1, deps: ["a"]),
] }

private var valid: Obj { ["id": "p", "title": "P", "anchorKind": "migrated", "reviewedAt": "2026-01-01", "steps": validSteps] }

private func with(_ extra: Obj) -> Obj { valid.merging(extra) { $1 } }
private func withSteps(_ steps: [Obj]) -> Obj { with(["steps": steps]) }

struct PlaybookImportTests {
    @Test func acceptsWellFormedFileAndFillsEmptyLists() {
        let r = validatePlaybook(valid)
        #expect(r.isOk)
        #expect(r.playbook?.steps[0].documents == [])
    }

    @Test func namesBothStepsOfACycleByTitle() {
        let r = validatePlaybook(withSteps([
            stepObj("a", "Book test", deps: ["b"]),
            stepObj("b", "Lodge EOI", deps: ["a"]),
        ]))
        #expect(r == .failure("Step \"Book test\" depends on \"Lodge EOI\", which depends back on it."))
    }

    @Test func rejectsAgeRangeThatEndsBeforeItStarts() {
        #expect(!validatePlaybook(with(["ages": ["from": 5, "to": 3]])).isOk)
        #expect(validatePlaybook(with(["ages": ["from": 4, "to": 5], "conditions": ["Ontario"]])).isOk)
    }

    @Test func namesStepWithMalformedConditionsList() {
        var s = validSteps[0]; s["conditions"] = "Ontario"
        let r = validatePlaybook(withSteps([s]))
        #expect(r.error?.contains("Book test") == true)
    }

    @Test func namesDanglingDependency() {
        let r = validatePlaybook(withSteps([stepObj("a", "Lodge", deps: ["ghost"])]))
        #expect(r.error?.contains("\"ghost\"") == true)
    }

    @Test(arguments: [
        (0, "review date"), (1, "anchorKind"), (2, "no steps"), (3, "offset"),
        (4, "duration"), (5, "validity"), (6, "share the id"), (7, "not a playbook"),
    ])
    func rejects(_ n: Int, _ message: String) {
        var noReview = valid; noReview["reviewedAt"] = nil
        let inputs: [Any] = [
            noReview,
            with(["anchorKind": ""]),
            withSteps([]),
            withSteps([stepObj("a", "A", offset: 1.5)]),
            withSteps([stepObj("a", "A", duration: -1)]),
            withSteps([stepObj("a", "A", extra: ["validForDays": 0])]),
            withSteps([stepObj("a", "A"), stepObj("a", "B")]),
            "nope",
        ]
        let r = validatePlaybook(inputs[n])
        #expect(!r.isOk)
        #expect(r.error?.contains(message) == true)
    }

    @Test func labelsPlaybookStaleAfterTwoYearsNeverBefore() throws {
        let p = try #require(validatePlaybook(valid).playbook)
        #expect(!isStale(p, "2027-12-31"))
        #expect(isStale(p, "2028-01-02"))
    }
}
