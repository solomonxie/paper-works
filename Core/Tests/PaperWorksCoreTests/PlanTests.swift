import Testing
@testable import PaperWorksCore

private let NOW = "2026-09-26"
private let anchors = [
    Anchor(id: "b", kind: "born", label: "Born", place: "Xi'an", date: "1991-04-12"),
    Anchor(id: "m", kind: "migrated", label: "Relocated to a country", place: "Canada", date: "2024-09-14"),
    Anchor(id: "v", kind: "visa-lodge", label: "Apply for permanent residence", date: "2027-12-01"),
]
private let tracks = [Track(id: "t", playbookId: "skilled-migration-ca", anchorId: "v", anchorEventDate: "2000-01-01")]
private let noInstances: [StepInstance] = []

struct PlanViewTests {
    let view = planView(bundledPlaybooks, tracks, anchors, noInstances, NOW)

    @Test func schedulesTrackOffItsAnchorNotStaleStoredDate() {
        let lodge = view.steps.first { $0.title.contains("Submit the permanent residence") }!
        #expect(lodge.dueBy == "2027-12-01")
    }

    @Test func namesTrackWhosePlaybookIsGone() {
        let v = planView([], tracks, anchors, noInstances, NOW)
        #expect(v.broken == [BrokenTrack(trackId: "t", error: "Its playbook is missing.")])
    }
}

struct TimelineTests {
    let view = planView(bundledPlaybooks, tracks, anchors, noInstances, NOW)

    @Test func readsKindsWithDetailAndAddsOnlyNextRoundBirthday() {
        let nodes = timelineNodes(anchors, tracks, view.steps, NOW)
        #expect(nodes.map(\.label) == ["Born · Xi'an", "Relocated to Canada", "Apply for permanent residence", "Turns 40"])
        #expect(nodes[3].date == "2031-04-12")
    }

    @Test func countsOpenStepsOnAnchorTheirTrackHangsOff() {
        let nodes = timelineNodes(anchors, tracks, view.steps, NOW)
        #expect(nodes.first { $0.id == "v" }!.pendingSteps == view.steps.count)
        #expect(nodes.first { $0.id == "m" }!.pendingSteps == 0)
    }

    @Test func namesCurrentChapterAfterKindThatOpenedIt() {
        let nodes = timelineNodes(anchors, tracks, view.steps, NOW)
        #expect(eventChapters(nodes, NOW).first { $0.isCurrent }!.label == "Settling in · Canada")
    }
}

struct DocumentTests {
    let pb = bundledPlaybooks.first { $0.id == "skilled-migration-ca" }!
    var language: StepTemplate { pb.steps.first { $0.id == "language-test" }! }
    var doneLanguage: [StepInstance] {
        [StepInstance(id: "i", trackId: "t", stepId: language.id, status: .done, completedOn: "2024-01-10",
                      checkedDocuments: [], checkedPrepare: [])]
    }

    @Test func derivesExpiryFromStepThatProducedIt() {
        let view = planView(bundledPlaybooks, tracks, anchors, doneLanguage, NOW)
        let doc = documentViews([], view, doneLanguage).first { $0.name == language.documents[0] }!
        #expect(doc.held)
        #expect(doc.expiresOn == addDays("2024-01-10", language.validForDays!))
    }

    @Test func documentDyingBeforeStepNeedsItIsExpiring() {
        let view = planView(bundledPlaybooks, tracks, anchors, doneLanguage, NOW)
        let docs = documentViews(
            [DocumentRecord(id: "passport", name: "Passport", issuedOn: "2018-01-01", expiresOn: "2027-01-01")],
            view, doneLanguage)
        let passport = groupDocuments(docs, NOW)[.expiring]!.first { $0.id == "passport" }!
        #expect(passport.clash!.gapDays > 0)
    }

    @Test func unheldDocumentIsMissingOrderedByFirstNeeded() {
        let view = planView(bundledPlaybooks, tracks, anchors, [], NOW)
        let missing = groupDocuments(documentViews([], view, []), NOW)[.missing]!
        let starts = missing.map { $0.neededBy?.startBy ?? "9999" }
        #expect(starts.sorted() == starts)
    }
}
