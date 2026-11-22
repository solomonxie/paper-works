import Testing
@testable import PaperWorksCore

private let NOW = "2026-09-26"
private let pb = Playbook(id: "p", title: "Track", anchorKind: "k", reviewedAt: NOW, steps: [])
private let opts = QueueOptions(leadDays: 14, hour: 9, digest: (1, 9))

private func step(_ n: Int, _ startBy: CivilDate, _ status: InstanceStatus = .pending) -> PlannedStep {
    PlannedStep(
        scheduled: ScheduledStep(stepId: "s\(n)", instanceId: "i\(n)", title: "Step \(n)", status: status, dueBy: startBy,
                                 startBy: startBy, earliestStart: nil, atRisk: false, blockedBy: [], expiresOn: nil,
                                 snoozedUntil: nil, blockedByLate: []),
        trackId: "t", playbook: pb,
        template: StepTemplate(id: "s\(n)", title: "Step \(n)", offsetDays: 0, durationDays: 0, dependsOn: [], documents: [], prepare: []),
        index: n, total: 0)
}

@Suite struct ReminderQueueTests {
    let many = (0..<300).map { step($0, addDays(NOW, 30 + $0)) }

    @Test func neverMoreThan64() {
        let q = buildQueue(many, NOW, opts)
        #expect(q.items.count == PENDING_LIMIT)
        #expect(q.items.filter { $0.weekday != nil }.count == 1)
        #expect(q.wanted == 300)
    }

    @Test func nearestFirstLeadDaysAhead() {
        let q = buildQueue(many, NOW, opts)
        #expect(q.items[0].id == "step:i0")
        #expect(q.items[0].date == addDays(NOW, 16))
        #expect(q.through == addDays(NOW, 30 + 62 - 14))
    }

    @Test func lateStepRemindsTomorrow() {
        let q = buildQueue([step(1, addDays(NOW, -5))], NOW, QueueOptions(leadDays: 14, hour: 9, digest: nil))
        #expect(q.items.count == 1)
        #expect(q.items[0].date == addDays(NOW, 1))
        #expect(q.items[0].body.hasPrefix("Start by today."))
    }

    @Test func skipsClosedSteps() {
        let q = buildQueue([step(1, NOW, .done), step(2, NOW, .skipped)], NOW, opts)
        #expect(q.items.map(\.id) == ["digest"])
    }
}
