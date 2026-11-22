import Testing
@testable import PaperWorksCore

private let NOW = "2026-09-26"

private func step(_ id: String, _ startBy: String, status: InstanceStatus = .pending,
                  dueBy: String? = nil, snoozedUntil: String? = nil) -> ScheduledStep {
    ScheduledStep(stepId: id, instanceId: "i-\(id)", title: id, status: status,
                  dueBy: dueBy ?? addDays(startBy, 30), startBy: startBy, earliestStart: nil,
                  atRisk: false, blockedBy: [], expiresOn: nil, snoozedUntil: snoozedUntil, blockedByLate: [])
}

struct RadarBucketTests {
    @Test func groupsByStartByLateAndImminentTogether() {
        #expect(bucketOf(step("late", addDays(NOW, -5)), NOW) == .now)
        #expect(bucketOf(step("soon", addDays(NOW, 14)), NOW) == .now)
        #expect(bucketOf(step("d", addDays(NOW, 15)), NOW) == .d90)
        #expect(bucketOf(step("y", addDays(NOW, 200)), NOW) == .year)
        #expect(bucketOf(step("l", addDays(NOW, 400)), NOW) == .later)
    }

    @Test func dueInYearsButSlowToObtainIsActNowToday() {
        #expect(bucketOf(step("slow", NOW, dueBy: addDays(NOW, 730)), NOW) == .now)
    }

    @Test func snoozePushesStepOutUntilSnoozeEnds() {
        #expect(bucketOf(step("s", NOW, status: .snoozed, snoozedUntil: addDays(NOW, 30)), NOW) == .d90)
    }

    @Test func leavesOutDoneAndSkippedAndSortsEachGroup() {
        let b = bucketize([
            step("b", addDays(NOW, 3)), step("a", addDays(NOW, 1)),
            step("done", NOW, status: .done), step("skip", NOW, status: .skipped),
        ], NOW)
        #expect(b[.now]!.map(\.stepId) == ["a", "b"])
    }
}

struct RadarDeltaTests {
    let before = [step("a", "2027-01-12"), step("b", "2027-02-01")]

    @Test func marksWhatMovedWhichWayAndFromWhere() {
        let after = [step("a", "2026-10-03"), step("b", "2027-03-01")]
        let moves = recordMoves([:], before, after, "Police check done", NOW)
        #expect(moves["i-a"]?.from == "2027-01-12")
        #expect(moves["i-a"]?.to == "2026-10-03")
        #expect(deltaOf(moves["i-a"]) == .earlier)
        #expect(deltaOf(moves["i-b"]) == .later)
    }

    @Test func keepsFirstWasDateAcrossRepeatedMovesClearsOnReturn() {
        let once = recordMoves([:], before, [step("a", "2027-01-01"), before[1]], "x", NOW)
        let twice = recordMoves(once, [step("a", "2027-01-01"), before[1]],
                                [step("a", "2026-12-01"), before[1]], "y", NOW)
        #expect(twice["i-a"]?.from == "2027-01-12")
        let back = recordMoves(twice, [step("a", "2026-12-01")], [step("a", "2027-01-12")], "z", NOW)
        #expect(back["i-a"] == nil)
    }

    @Test func forgetsMoveAfterTwoWeeks() {
        let moves = recordMoves([:], before, [step("a", "2027-01-01"), before[1]], "x", NOW)
        #expect(recordMoves(moves, before, before, "noop", addDays(NOW, 15)) == [:])
    }

    @Test func neverMarksTheStepTheUserTouched() {
        let after = [step("a", "2026-10-03"), before[1]]
        #expect(recordMoves([:], before, after, "x", NOW, ["i-a"]) == [:])
        #expect(summarize(before, after, ["i-a"]).moved == 0)
    }

    @Test func summarizesCountAndDominantDirection() {
        let s = summarize(before, [step("a", "2026-10-03"), step("b", "2027-01-01")])
        #expect(s.moved == 2)
        #expect(s.direction == .earlier)
    }
}
