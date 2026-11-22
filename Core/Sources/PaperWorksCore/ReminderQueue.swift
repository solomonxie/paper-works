import Foundation

/// iOS holds at most 64 pending local notifications per app.
public let PENDING_LIMIT = 64

public struct NativeReminder: Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    /// One-off: civil date. Repeating: weekday (1 = Sunday).
    public var date: CivilDate?
    public var weekday: Int?
    public var hour: Int
    public var target: String

    public init(id: String, title: String, body: String, date: CivilDate? = nil, weekday: Int? = nil, hour: Int, target: String) {
        self.id = id; self.title = title; self.body = body; self.date = date; self.weekday = weekday
        self.hour = hour; self.target = target
    }
}

public struct QueuePlan: Equatable, Sendable {
    public var items: [NativeReminder]
    /// Open steps that deserve a reminder, queued or not.
    public var wanted: Int
    /// Date of the last one-off reminder handed to iOS.
    public var through: CivilDate?
}

private let WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
public func weekdayName(_ w: Int) -> String { WEEKDAYS[((w - 1) % 7 + 7) % 7] }

public struct QueueOptions: Sendable {
    public var leadDays: Int
    public var hour: Int
    public var digest: (weekday: Int, hour: Int)?
    public init(leadDays: Int, hour: Int, digest: (weekday: Int, hour: Int)?) {
        self.leadDays = leadDays; self.hour = hour; self.digest = digest
    }
}

/// The nearest reminders that fit under the cap, one per open step at `startBy − leadDays` (never in the past), plus the weekly digest.
public func buildQueue(_ steps: [PlannedStep], _ now: CivilDate, _ opts: QueueOptions) -> QueuePlan {
    let tomorrow = addDays(now, 1)
    let candidates = steps
        .filter { isOpen($0.scheduled) }
        .map { (step: $0, on: maxDate(addDays(attentionDate($0.scheduled), -opts.leadDays), tomorrow)) }
        .enumerated()
        .sorted { $0.element.on != $1.element.on ? $0.element.on < $1.element.on : $0.offset < $1.offset }
        .map(\.element)

    let room = PENDING_LIMIT - (opts.digest != nil ? 1 : 0)
    let chosen = candidates.prefix(room)

    var items: [NativeReminder] = chosen.map { step, on in
        let due = attentionDate(step.scheduled)
        let when = due <= on ? "today" : "\(formatShort(due)) · \(formatRelative(due, now: on))"
        return NativeReminder(id: "step:\(step.scheduled.instanceId)", title: step.scheduled.title,
                              body: "Start by \(when). \(step.playbook.title)", date: on, hour: opts.hour,
                              target: "step:\(step.scheduled.instanceId)")
    }
    if let d = opts.digest {
        items.append(NativeReminder(id: "digest", title: "This week in your plan",
                                    body: "Open the Radar to see what needs starting.", weekday: d.weekday,
                                    hour: d.hour, target: "radar"))
    }
    return QueuePlan(items: items, wanted: candidates.count, through: chosen.last?.on)
}
