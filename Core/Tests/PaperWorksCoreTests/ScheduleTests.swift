import Testing
@testable import PaperWorksCore

private let ANCHOR = "2027-01-01"

private let track = Track(id: "t", playbookId: "p", anchorEventDate: ANCHOR)

private func step(_ id: String, _ title: String, _ offset: Int, _ duration: Int, end: Int? = nil,
                  purposes: [String]? = nil, valid: Int? = nil, deps: [String] = []) -> StepTemplate {
    StepTemplate(id: id, title: title, offsetDays: offset, endOffsetDays: end, purposes: purposes,
                 durationDays: duration, validForDays: valid, dependsOn: deps, documents: [], prepare: [])
}

private func playbook(_ steps: [StepTemplate]) -> Playbook {
    Playbook(id: "p", title: "Test", anchorKind: "k", reviewedAt: "2026-09-26", steps: steps)
}

private func pending(_ ids: [String]) -> [StepInstance] {
    ids.map { StepInstance(id: "i-\($0)", trackId: "t", stepId: $0, status: .pending, checkedDocuments: [], checkedPrepare: []) }
}

private func done(_ instances: [StepInstance], _ stepId: String, _ on: String) -> [StepInstance] {
    instances.map { i in
        guard i.stepId == stepId else { return i }
        var c = i; c.status = .done; c.completedOn = on; return c
    }
}

private func index(_ steps: [ScheduledStep]) -> [String: ScheduledStep] {
    Dictionary(uniqueKeysWithValues: steps.map { ($0.stepId, $0) })
}

private let chain = playbook([
    step("a", "A", -100, 10),
    step("b", "B", -50, 20, valid: 30, deps: ["a"]),
    step("c", "C", 0, 5, deps: ["b"]),
])

private func sched(_ pb: Playbook, _ t: Track, _ i: [StepInstance], now: CivilDate? = nil) -> [ScheduledStep] {
    try! schedule(pb, t, i, now: now)
}

struct BackwardSchedulingTests {
    @Test func derivesDueByFromAnchorAndOffset() {
        let s = index(sched(chain, track, pending(["a", "b", "c"])))
        #expect(s["a"]!.dueBy == addDays(ANCHOR, -100))
        #expect(s["c"]!.dueBy == ANCHOR)
    }

    @Test func startsJustInTime() {
        let s = index(sched(chain, track, pending(["a", "b", "c"])))
        #expect(diffDays(s["a"]!.startBy, s["a"]!.dueBy) == 10)
        #expect(diffDays(s["c"]!.startBy, s["c"]!.dueBy) == 5)
    }

    @Test func clampsHowEarlyAResultMayBeObtained() {
        let s = index(sched(chain, track, pending(["a", "b", "c"])))
        #expect(diffDays(s["b"]!.earliestStart!, s["b"]!.dueBy) == 50)
        #expect(s["a"]!.earliestStart == nil)
    }

    @Test func listsOutstandingDependenciesAndDropsThemOnceDone() {
        let instances = pending(["a", "b", "c"])
        #expect(index(sched(chain, track, instances))["b"]!.blockedBy == ["a"])
        #expect(index(sched(chain, track, done(instances, "a", "2026-01-01")))["b"]!.blockedBy == [])
    }
}

struct ReflowTests {
    let tight = playbook([
        step("a", "A", -100, 100),
        step("b", "B", -150, 10, deps: ["a"]),
    ])

    @Test func dependencyFinishingLatePushesSuccessor() {
        let s = index(sched(tight, track, pending(["a", "b"])))
        #expect(s["b"]!.startBy == addDays(ANCHOR, -100))
        #expect(s["b"]!.atRisk == true)
    }

    @Test func finishingEarlyMovesSuccessorsEarlier() {
        let before = index(sched(tight, track, pending(["a", "b"])))
        let after = index(sched(tight, track, done(pending(["a", "b"]), "a", addDays(ANCHOR, -280))))
        #expect(after["b"]!.startBy < before["b"]!.startBy)
        #expect(after["b"]!.atRisk == false)
    }

    @Test func movingAnchorShiftsEveryPendingDate() {
        let base = index(sched(chain, track, pending(["a", "b", "c"])))
        var t = track; t.anchorEventDate = addDays(ANCHOR, 120)
        let moved = index(sched(chain, t, pending(["a", "b", "c"])))
        for id in ["a", "b", "c"] {
            #expect(diffDays(base[id]!.dueBy, moved[id]!.dueBy) == 120)
            #expect(diffDays(base[id]!.startBy, moved[id]!.startBy) == 120)
        }
    }

    @Test func doneStepKeepsRealDateWhenAnchorMoves() {
        let realDate = "2026-03-04"
        let instances = done(pending(["a", "b", "c"]), "a", realDate)
        for shift in [0, 120, -400] {
            var t = track; t.anchorEventDate = addDays(ANCHOR, shift)
            #expect(index(sched(chain, t, instances))["a"]!.startBy == realDate)
        }
    }

    @Test func recordsWhenCompletedResultExpires() {
        let s = index(sched(chain, track, done(pending(["a", "b", "c"]), "b", "2026-05-01")))
        #expect(s["b"]!.expiresOn == "2026-05-31")
        #expect(s["a"]!.expiresOn == nil)
    }
}

struct PlaybookValidityTests {
    @Test func ordersDependencyFirst() throws {
        let ids = try topoSort(chain.steps).map(\.id)
        #expect(ids.firstIndex(of: "a")! < ids.firstIndex(of: "b")!)
        #expect(ids.firstIndex(of: "b")! < ids.firstIndex(of: "c")!)
    }

    @Test func rejectsCycle() {
        let cyclic = playbook([step("x", "X", 0, 1, deps: ["y"]), step("y", "Y", 0, 1, deps: ["x"])])
        #expect(throws: PlaybookCycleError.self) { try schedule(cyclic, track, pending(["x", "y"])) }
    }

    @Test func namesMissingDependency() {
        let dangling = playbook([step("x", "X", 0, 1, deps: ["ghost"])])
        #expect(throws: MissingDependencyError.self) { try schedule(dangling, track, pending(["x"])) }
    }
}

struct ExpiryClashTests {
    @Test func flagsResultDyingBeforeConsumerDue() {
        let instances = done(pending(["a", "b", "c"]), "b", "2026-05-01")
        let clashes = expiryClashes(sched(chain, track, instances), chain)
        #expect(clashes.count == 1)
        #expect(clashes[0].source.stepId == "b")
        #expect(clashes[0].consumer.stepId == "c")
    }

    @Test func staysQuietWhenStillValid() {
        let instances = done(pending(["a", "b", "c"]), "b", addDays(ANCHOR, -10))
        #expect(expiryClashes(sched(chain, track, instances), chain).isEmpty)
    }
}

struct UserOverrideTests {
    let instances = pending(["a", "b", "c"])

    @Test func skippedStepHoldsNothingUp() {
        let skipped = instances.map { i -> StepInstance in
            var c = i; if c.stepId == "b" { c.status = .skipped }; return c
        }
        let s = index(sched(chain, track, skipped))
        #expect(s["c"]!.blockedBy == [])
        #expect(s["c"]!.startBy == addDays(ANCHOR, -5))
    }

    @Test func movedDueDateReplacesAnchorPlusOffset() {
        let moved = instances.map { i -> StepInstance in
            var c = i; if c.stepId == "c" { c.dueOverride = "2027-03-01" }; return c
        }
        let s = index(sched(chain, track, moved))
        #expect(s["c"]!.dueBy == "2027-03-01")
        #expect(s["a"]!.dueBy == addDays(ANCHOR, -100))
    }

    @Test func flagsSuccessorWhoseDependencyIsLate() {
        let s = index(sched(chain, track, instances, now: addDays(ANCHOR, -95)))
        #expect(s["b"]!.blockedByLate == ["a"])
        #expect(s["c"]!.blockedByLate == [])
    }
}

struct PlanRedoTests {
    @Test func insertsRepeatThatClearsClashAndHoldsConsumer() {
        let instances = done(pending(["a", "b", "c"]), "b", "2026-05-01")
        let before = sched(chain, track, instances)
        let clash = expiryClashes(before, chain, track)[0]
        #expect(clash.gapDays == diffDays("2026-05-31", ANCHOR))

        let redone = planRedo(chain, track, "b", "c", before)
        let after = index(sched(chain, redone, instances))
        let redo = after["b~redo1"]!
        #expect(redo.dueBy == before.first { $0.stepId == "c" }!.startBy)
        #expect(after["c"]!.blockedBy.contains("b~redo1"))
        #expect(expiryClashes(Array(after.values), chain, redone).isEmpty)
    }

    @Test func finishedConsumerNoLongerClashes() {
        var instances = done(pending(["a", "b", "c"]), "b", "2026-05-01")
        instances = done(instances, "c", "2026-05-10")
        #expect(expiryClashes(sched(chain, track, instances), chain).isEmpty)
    }
}

struct EventsWithEndTests {
    let trip = playbook([
        step("insure", "Insure", -14, 3),
        step("i94", "Check departure", 30, 1, end: 14),
    ])

    @Test func countsFromEndOnceThereIsOne() {
        var t = track; t.anchorEnd = "2027-01-20"
        let s = index(sched(trip, t, pending(["insure", "i94"])))
        #expect(s["insure"]!.dueBy == "2026-12-18")
        #expect(s["i94"]!.dueBy == "2027-02-03")
    }

    @Test func usesStartBasedEstimateWithoutEnd() {
        let s = index(sched(trip, track, pending(["insure", "i94"])))
        #expect(s["i94"]!.dueBy == "2027-01-31")
    }

    @Test func keepsDoneEndBasedStepPinnedWhenEndMoves() {
        let inst = done(pending(["insure", "i94"]), "i94", "2027-01-25")
        var t = track; t.anchorEnd = "2027-03-01"
        #expect(index(sched(trip, t, inst))["i94"]!.startBy == "2027-01-25")
    }

    @Test func redoOfEndBasedStepLandsWhereConsumerNeedsIt() {
        let pb = playbook([
            step("a", "A", 0, 2, end: 0, valid: 5),
            step("b", "B", 40, 1, deps: ["a"]),
        ])
        var t = track; t.anchorEnd = "2027-01-10"
        let scheduled = sched(pb, t, pending(["a", "b"]))
        let next = planRedo(pb, t, "a", "b", scheduled)
        let redo = next.extraSteps![0]
        #expect(redo.endOffsetDays == nil)
        #expect(addDays(ANCHOR, redo.offsetDays) == index(scheduled)["b"]!.startBy)
    }
}

struct TripPurposeTests {
    let pb = playbook([
        step("ticket", "Return ticket", -30, 1),
        step("invite", "Invitation letter", -20, 7, purposes: ["business"]),
        step("pack", "Pack", -1, 1, deps: ["invite", "ticket"]),
    ])

    @Test func dropsStepsForAnotherPurposeAndWhatWaitedOnThem() {
        var t = track; t.purpose = "leisure"
        let list = sched(pb, t, pending(["ticket", "invite", "pack"]))
        #expect(list.map(\.stepId) == ["ticket", "pack"])
        #expect(index(list)["pack"]!.blockedBy == ["ticket"])
    }

    @Test func keepsEveryStepWhilePurposeUnset() {
        #expect(sched(pb, track, pending(["ticket", "invite", "pack"])).map(\.stepId) == ["ticket", "invite", "pack"])
    }

    @Test func stillNamesMissingDependency() {
        let broken = playbook([step("x", "X", 0, 1, deps: ["ghost"])])
        var t = track; t.purpose = "leisure"
        #expect(throws: MissingDependencyError.self) { try schedule(broken, t, []) }
    }
}
