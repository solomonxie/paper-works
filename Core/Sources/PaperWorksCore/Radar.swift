import Foundation

public enum Bucket: String, CaseIterable, Sendable { case now, d90, year, later }

public let BUCKETS: [Bucket] = [.now, .d90, .year, .later]

/// Anything to start within this many days counts as "act now".
public let ACT_NOW_DAYS = 14

/// How long a ▲▼ stays on a row after the reflow that caused it.
public let MOVE_VISIBLE_DAYS = 14

/// What a step needs to be bucketed; `ScheduledStep` and `PlannedStep` both qualify.
public protocol Stepped {
    var scheduled: ScheduledStep { get }
}

extension ScheduledStep: Stepped { public var scheduled: ScheduledStep { self } }

/// When a step next asks for attention: its start-by, or the end of a snooze.
public func attentionDate(_ step: ScheduledStep) -> CivilDate {
    if let s = step.snoozedUntil { return maxDate(step.startBy, s) }
    return step.startBy
}

public func isOpen(_ step: ScheduledStep) -> Bool { step.status == .pending || step.status == .snoozed }

public func bucketOf(_ step: ScheduledStep, _ now: CivilDate) -> Bucket {
    let on = attentionDate(step)
    if on <= addDays(now, ACT_NOW_DAYS) { return .now }
    if on <= addDays(now, 90) { return .d90 }
    if on <= addDays(now, 365) { return .year }
    return .later
}

/// Open steps grouped by how soon they must be *started*, not by due date.
public func bucketize<T: Stepped>(_ steps: [T], _ now: CivilDate) -> [Bucket: [T]] {
    var out: [Bucket: [T]] = [.now: [], .d90: [], .year: [], .later: []]
    for step in steps where isOpen(step.scheduled) { out[bucketOf(step.scheduled, now)]!.append(step) }
    for b in BUCKETS {
        out[b]!.sort { attentionDate($0.scheduled) < attentionDate($1.scheduled) }
    }
    return out
}

/// Folds one reflow into the running set of visible moves.
public func recordMoves(
    _ previous: Moves,
    _ before: [ScheduledStep],
    _ after: [ScheduledStep],
    _ cause: String,
    _ now: CivilDate,
    _ exclude: [String] = []
) -> Moves {
    var was: [String: ScheduledStep] = [:]
    for s in before { was[s.instanceId] = s }
    var next: Moves = [:]
    let cutoff = addDays(now, -MOVE_VISIBLE_DAYS)

    for (id, move) in previous where move.on >= cutoff { next[id] = move }

    for step in after {
        guard let old = was[step.instanceId], isOpen(step), !exclude.contains(step.instanceId) else { continue }
        if old.startBy == step.startBy { continue }
        let from = next[step.instanceId]?.from ?? old.startBy
        if from == step.startBy {
            next[step.instanceId] = nil
        } else {
            next[step.instanceId] = Move(from: from, to: step.startBy, on: now, cause: cause)
        }
    }
    return next
}

public enum Delta: String, Sendable { case earlier, later }

public func deltaOf(_ move: Move?) -> Delta? {
    guard let move else { return nil }
    return move.to < move.from ? .earlier : .later
}

/// Summary for the toast: how many moved and which way most of them went.
public func summarize(
    _ before: [ScheduledStep],
    _ after: [ScheduledStep],
    _ exclude: [String] = []
) -> (moved: Int, direction: Delta) {
    var was: [String: CivilDate] = [:]
    for s in before { was[s.instanceId] = s.startBy }
    var earlier = 0, later = 0
    for step in after {
        guard let old = was[step.instanceId], isOpen(step), !exclude.contains(step.instanceId) else { continue }
        if step.startBy < old { earlier += 1 } else if step.startBy > old { later += 1 }
    }
    return (earlier + later, later > earlier ? .later : .earlier)
}
