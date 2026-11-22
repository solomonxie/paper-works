import Foundation

public struct PlaybookCycleError: Error, Equatable, CustomStringConvertible {
    public let stepIds: [String]
    public var description: String { "Cyclic dependency between steps: \(stepIds.joined(separator: " → "))" }
}

public struct MissingDependencyError: Error, Equatable, CustomStringConvertible {
    public let stepId: String
    public let missingId: String
    public var description: String { "Step \"\(stepId)\" depends on \"\(missingId)\", which does not exist" }
}

/// Dependency order, so a step is always scheduled after everything it needs.
public func topoSort(_ steps: [StepTemplate]) throws -> [StepTemplate] {
    var byId: [String: StepTemplate] = [:]
    for s in steps { byId[s.id] = s }
    var closed = Set<String>()
    var open = Set<String>()
    var out: [StepTemplate] = []

    func visit(_ step: StepTemplate, _ path: [String]) throws {
        if closed.contains(step.id) { return }
        if open.contains(step.id) { throw PlaybookCycleError(stepIds: path + [step.id]) }
        open.insert(step.id)
        for depId in step.dependsOn {
            guard let dep = byId[depId] else { throw MissingDependencyError(stepId: step.id, missingId: depId) }
            try visit(dep, path + [step.id])
        }
        open.remove(step.id)
        closed.insert(step.id)
        out.append(step)
    }

    for step in steps { try visit(step, []) }
    return out
}

private func forPurpose(_ step: StepTemplate, _ purpose: String?) -> Bool {
    guard let purpose, !purpose.isEmpty, let purposes = step.purposes else { return true }
    return purposes.contains(purpose)
}

/// The playbook as this track sees it: its own steps plus any the user added,
/// minus steps for another trip purpose. A dropped step no longer holds up the steps after it.
public func effectiveSteps(_ playbook: Playbook, _ track: Track) -> [StepTemplate] {
    let extraDeps = track.extraDependsOn ?? [:]
    let all = playbook.steps + (track.extraSteps ?? [])
    let dropped = Set(all.filter { !forPurpose($0, track.purpose) }.map(\.id))
    return all.filter { !dropped.contains($0.id) }.map { step in
        var s = step
        s.dependsOn = (step.dependsOn + (extraDeps[step.id] ?? [])).filter { !dropped.contains($0) }
        return s
    }
}

/// Schedules a track backward from its anchor event.
///
///     dueBy         = anchorDate + offsetDays, or anchorEnd + endOffsetDays once it has an end
///     latestStart   = dueBy - durationDays
///     earliestStart = dueBy - validForDays - durationDays
///     startBy       = max(latestStart, when every dependency actually finishes)
///
/// A done step is pinned to the date it really happened. A skipped step holds nothing up.
public func schedule(_ playbook: Playbook, _ track: Track, _ instances: [StepInstance], now: CivilDate? = nil) throws -> [ScheduledStep] {
    var byStepId: [String: StepInstance] = [:]
    for i in instances { byStepId[i.stepId] = i }
    var finishOf: [String: CivilDate] = [:]
    var lateIds = Set<String>()
    var result: [ScheduledStep] = []

    for step in try topoSort(effectiveSteps(playbook, track)) {
        let instance = byStepId[step.id]
        let status = instance?.status ?? .pending
        let dueBy: CivilDate
        if let o = instance?.dueOverride {
            dueBy = o
        } else if let end = track.anchorEnd, let eo = step.endOffsetDays {
            dueBy = addDays(end, eo)
        } else {
            dueBy = addDays(track.anchorEventDate, step.offsetDays)
        }
        let latestStart = addDays(dueBy, -step.durationDays)
        let earliestStart = step.validForDays.map { addDays(dueBy, -$0 - step.durationDays) }

        let depFinishes = step.dependsOn.compactMap { finishOf[$0] }
        let startBy = depFinishes.reduce(latestStart) { max($0, $1) }

        let doneOn: CivilDate? = status == .done ? instance?.completedOn : nil
        if status != .skipped {
            finishOf[step.id] = doneOn ?? addDays(startBy, step.durationDays)
        }

        let blockedBy = step.dependsOn.filter {
            let s = byStepId[$0]?.status
            return s != .done && s != .skipped
        }
        if doneOn == nil, status != .skipped, let now, startBy < now { lateIds.insert(step.id) }

        result.append(ScheduledStep(
            stepId: step.id,
            instanceId: instance?.id ?? "unbound:\(step.id)",
            title: step.title,
            status: status,
            dueBy: dueBy,
            startBy: doneOn ?? startBy,
            earliestStart: earliestStart,
            atRisk: startBy > latestStart,
            blockedBy: blockedBy,
            expiresOn: doneOn.flatMap { d in step.validForDays.map { addDays(d, $0) } },
            snoozedUntil: status == .snoozed ? instance?.snoozedUntil : nil,
            blockedByLate: blockedBy.filter { lateIds.contains($0) }
        ))
    }
    return result
}

public struct ExpiryClash: Equatable, Sendable {
    public var source: ScheduledStep
    public var consumer: ScheduledStep
    /// Days between the result expiring and the consumer's due date.
    public var gapDays: Int
}

/// A held result that dies before the step needing it comes due. Settled once
/// the consumer is finished, or once a redo of the source is planned for it.
public func expiryClashes(_ scheduled: [ScheduledStep], _ playbook: Playbook, _ track: Track? = nil) -> [ExpiryClash] {
    let steps = track.map { effectiveSteps(playbook, $0) } ?? playbook.steps
    var templates: [String: StepTemplate] = [:]
    for s in steps { templates[s.id] = s }
    var byId: [String: ScheduledStep] = [:]
    for s in scheduled { byId[s.stepId] = s }
    var clashes: [ExpiryClash] = []

    for step in steps {
        guard let consumer = byId[step.id], consumer.status != .done, consumer.status != .skipped else { continue }
        for depId in step.dependsOn {
            let redone = step.dependsOn.contains { templates[$0]?.redoOf == depId }
            if let source = byId[depId], let expires = source.expiresOn, expires < consumer.dueBy, !redone {
                clashes.append(ExpiryClash(source: source, consumer: consumer, gapDays: diffDays(expires, consumer.dueBy)))
            }
        }
    }
    return clashes
}

/// Inserts a repeat of `sourceId` that finishes by the time `consumerId` needs
/// to start, and makes the consumer wait for it. Returns the new track; the caller reflows.
public func planRedo(_ playbook: Playbook, _ track: Track, _ sourceId: String, _ consumerId: String, _ scheduled: [ScheduledStep]) -> Track {
    let steps = effectiveSteps(playbook, track)
    guard let source = steps.first(where: { $0.id == sourceId }),
          let consumer = scheduled.first(where: { $0.stepId == consumerId }) else { return track }

    let base = source.redoOf ?? source.id
    let taken = Set(steps.map(\.id))
    var n = 1
    while taken.contains("\(base)~redo\(n)") { n += 1 }
    let id = "\(base)~redo\(n)"

    var redo = source
    redo.id = id
    redo.title = "\(source.title) (redo)"
    redo.offsetDays = diffDays(track.anchorEventDate, consumer.startBy)
    redo.endOffsetDays = nil
    redo.redoOf = sourceId

    var next = track
    next.extraSteps = (track.extraSteps ?? []) + [redo]
    var deps = track.extraDependsOn ?? [:]
    deps[consumerId] = (deps[consumerId] ?? []) + [id]
    next.extraDependsOn = deps
    return next
}
