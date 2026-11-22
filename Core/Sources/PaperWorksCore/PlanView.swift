import Foundation

/// A scheduled step with enough context to draw it anywhere.
@dynamicMemberLookup
public struct PlannedStep: Equatable, Stepped, Sendable {
    public var scheduled: ScheduledStep
    public var trackId: String
    public var playbook: Playbook
    public var template: StepTemplate
    /// 1-based position in the track's dependency order.
    public var index: Int
    public var total: Int

    public subscript<V>(dynamicMember key: KeyPath<ScheduledStep, V>) -> V { scheduled[keyPath: key] }
}

public struct PlannedClash: Equatable, Sendable {
    public var source: ScheduledStep
    public var consumer: ScheduledStep
    public var gapDays: Int
    public var trackId: String
}

public struct BrokenTrack: Equatable, Sendable {
    public var trackId: String
    public var error: String
    public init(trackId: String, error: String) { self.trackId = trackId; self.error = error }
}

public struct PlanView: Sendable {
    public var steps: [PlannedStep] = []
    public var clashes: [PlannedClash] = []
    /// Tracks that couldn't be scheduled, with the reason.
    public var broken: [BrokenTrack] = []
    public init(steps: [PlannedStep] = [], clashes: [PlannedClash] = [], broken: [BrokenTrack] = []) {
        self.steps = steps; self.clashes = clashes; self.broken = broken
    }
}

/// The date a track hangs off: its anchor, resolved for precision.
public func trackAnchorDate(_ track: Track, _ anchors: [Anchor]) -> CivilDate {
    if let a = anchors.first(where: { $0.id == track.anchorId }) { return resolve(a.date, a.precision) }
    return track.anchorEventDate
}

/// What a track reads off its anchor: start, end and trip purpose.
public func fromAnchor(_ a: Anchor) -> (anchorEventDate: CivilDate, anchorEnd: CivilDate?, purpose: String?) {
    (resolve(a.date, a.precision), a.end.map { resolve($0, a.precision) }, a.purpose)
}

/// The track with its anchor's current dates and purpose.
public func anchoredTrack(_ track: Track, _ anchors: [Anchor]) -> Track {
    guard let id = track.anchorId, let a = anchors.first(where: { $0.id == id }) else { return track }
    var t = track
    let f = fromAnchor(a)
    t.anchorEventDate = f.anchorEventDate
    t.anchorEnd = f.anchorEnd
    t.purpose = f.purpose
    return t
}

private func message(_ error: Error) -> String {
    (error as? CustomStringConvertible)?.description ?? error.localizedDescription
}

/// Every attached track, scheduled. The only place the screens get dates from.
public func planView(
    _ playbooks: [Playbook],
    _ tracks: [Track],
    _ anchors: [Anchor],
    _ instances: [StepInstance],
    _ now: CivilDate
) -> PlanView {
    var view = PlanView()
    for t in tracks {
        guard let playbook = playbooks.first(where: { $0.id == t.playbookId }) else {
            view.broken.append(BrokenTrack(trackId: t.id, error: "Its playbook is missing."))
            continue
        }
        let track = anchoredTrack(t, anchors)
        let mine = instances.filter { $0.trackId == t.id }
        do {
            let scheduled = try schedule(playbook, track, mine, now: now)
            var templates: [String: StepTemplate] = [:]
            for s in effectiveSteps(playbook, track) { templates[s.id] = s }
            for (i, s) in scheduled.enumerated() {
                view.steps.append(PlannedStep(
                    scheduled: s, trackId: t.id, playbook: playbook, template: templates[s.stepId]!,
                    index: i + 1, total: scheduled.count))
            }
            for c in expiryClashes(scheduled, playbook, track) {
                view.clashes.append(PlannedClash(source: c.source, consumer: c.consumer, gapDays: c.gapDays, trackId: t.id))
            }
        } catch {
            view.broken.append(BrokenTrack(trackId: t.id, error: message(error)))
        }
    }
    return view
}

public func openSteps(_ steps: [PlannedStep]) -> [PlannedStep] { steps.filter { isOpen($0.scheduled) } }

/// Past their due date, the only steps shown in red.
public func lateSteps(_ steps: [PlannedStep], _ now: CivilDate) -> [PlannedStep] {
    openSteps(steps).filter { $0.dueBy < now && $0.snoozedUntil == nil }
}

// MARK: Timeline

public struct TimelineNode: Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var date: CivilDate
    public var source: LifeEvent.Source
    public var anchorId: String?
    public var chapterLabel: String?
    public var precision: DatePrecision
    public var pendingSteps: Int
    /// On the line, but doesn't open a chapter.
    public var moment: Bool?
    /// When it ends, for kinds that last.
    public var end: CivilDate?

    var lifeEvent: LifeEvent {
        LifeEvent(id: id, label: label, date: date, source: source, anchorId: anchorId, chapterLabel: chapterLabel)
    }
}

public func anchorDisplay(_ anchor: Anchor) -> String {
    anchorTitle(anchor.kind, anchor.label, anchor.place)
}

/// Anchors plus the one derived milestone worth showing: the next round birthday.
public func timelineNodes(
    _ anchors: [Anchor],
    _ tracks: [Track],
    _ steps: [PlannedStep],
    _ now: CivilDate
) -> [TimelineNode] {
    var nodes: [TimelineNode] = anchors.map { a in
        let kind = kindById(a.kind)
        let trackIds = Set(tracks.filter { $0.anchorId == a.id }.map(\.id))
        return TimelineNode(
            id: a.id,
            label: anchorDisplay(a),
            date: resolve(a.date, a.precision),
            source: .anchor,
            anchorId: a.id,
            chapterLabel: kind.map { k in a.place.map { "\(k.chapter) · \($0)" } ?? k.chapter },
            precision: a.precision,
            pendingSteps: openSteps(steps).filter { trackIds.contains($0.trackId) }.count,
            moment: kind?.moment,
            end: a.end.map { resolve($0, a.precision) }
        )
    }

    if let born = anchors.first(where: { $0.kind == "born" }) {
        let birth = resolve(born.date, born.precision)
        let age = yearsBetween(birth, now)
        let next = (age / 10 + 1) * 10
        let p = birth.split(separator: "-").map(String.init)
        let day = p[1] == "02" && p[2] == "29" ? "28" : p[2]
        nodes.append(TimelineNode(
            id: "turns-\(next)", label: "Turns \(next)",
            date: "\(Int(p[0])! + next)-\(p[1])-\(day)",
            source: .derived, precision: born.precision == .day ? .day : .year, pendingSteps: 0))
    }

    return nodes.sorted { $0.date < $1.date }
}

public func eventChapters(_ nodes: [TimelineNode], _ now: CivilDate) -> [Chapter] {
    deriveChapters(nodes.filter { $0.source == .anchor && $0.moment != true }.map(\.lifeEvent), now)
}

public func ageOn(_ anchors: [Anchor], _ now: CivilDate) -> Int? {
    guard let born = anchors.first(where: { $0.kind == "born" }) else { return nil }
    return yearsBetween(resolve(born.date, born.precision), now)
}

/// Steps whose due date falls inside the chapter.
public func chapterSteps(_ chapter: Chapter, _ steps: [PlannedStep]) -> [PlannedStep] {
    steps.filter { $0.dueBy >= chapter.start && (chapter.end == nil || $0.dueBy < chapter.end!) }
}

// MARK: Documents

public func docId(_ name: String) -> String {
    var s = name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
    while s.hasPrefix("-") { s.removeFirst() }
    while s.hasSuffix("-") { s.removeLast() }
    return s
}

public struct DocClash: Equatable, Sendable {
    /// It dies before a step that needs it comes due.
    public var consumer: PlannedStep
    public var source: PlannedStep?
    public var gapDays: Int
}

public struct DocView: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var record: DocumentRecord?
    public var held: Bool
    public var issuedOn: CivilDate?
    public var expiresOn: CivilDate?
    /// Every step that lists this document, in schedule order.
    public var askedBy: [PlannedStep]
    /// The next open step that lists it.
    public var neededBy: PlannedStep?
    public var clash: DocClash?
}

public enum DocGroup: String, CaseIterable, Sendable { case expiring, held, missing }

/// Soon enough to belong in EXPIRING even without a clash.
public let EXPIRING_DAYS = 180

private func same(_ a: PlannedStep?, _ b: PlannedStep?) -> Bool {
    guard let a, let b else { return false }
    return a.trackId == b.trackId && a.instanceId == b.instanceId
}

public func documentViews(
    _ records: [DocumentRecord],
    _ view: PlanView,
    _ instances: [StepInstance]
) -> [DocView] {
    var order: [String] = []
    var names: [String: String] = [:]
    func put(_ id: String, _ name: String) {
        if names[id] == nil { order.append(id) }
        names[id] = name
    }
    for s in view.steps { for n in s.template.documents { put(docId(n), n) } }
    for r in records { put(r.id, r.name) }

    let checked = Set(instances.flatMap { $0.checkedDocuments.map(docId) })

    return order.map { id in
        let name = names[id]!
        let record = records.first { $0.id == id }
        let askedBy = view.steps
            .filter { $0.template.documents.contains { docId($0) == id } }
            .sorted { $0.dueBy < $1.dueBy }
        let producer = askedBy.first { $0.status == .done && $0.expiresOn != nil }
        let validity = askedBy.first { $0.template.validForDays != nil }?.template.validForDays
        let issued = record?.issuedOn ?? producer?.startBy
        var expiresOn = record?.expiresOn ?? producer?.expiresOn
        if expiresOn == nil, let issued, let validity, record?.noExpiry != true {
            expiresOn = addDays(issued, validity)
        }
        let held = record?.issuedOn != nil || checked.contains(id) || producer != nil
        let neededBy = askedBy.first { isOpen($0.scheduled) && !same($0, producer) }

        var clash: DocClash?
        let engine = producer.flatMap { p in
            view.clashes.first { $0.source.stepId == p.stepId && $0.trackId == p.trackId }
        }
        if let engine {
            let consumer = view.steps.first { $0.trackId == engine.trackId && $0.stepId == engine.consumer.stepId }!
            clash = DocClash(consumer: consumer, source: producer, gapDays: engine.gapDays)
        } else if held, let expiresOn {
            if let after = askedBy.first(where: { isOpen($0.scheduled) && !same($0, producer) && expiresOn < $0.dueBy }) {
                clash = DocClash(consumer: after, source: nil, gapDays: diffDays(expiresOn, after.dueBy))
            }
        }

        return DocView(
            id: id, name: name, record: record, held: held,
            issuedOn: record?.issuedOn ?? producer?.startBy,
            expiresOn: expiresOn, askedBy: askedBy, neededBy: neededBy, clash: clash)
    }
}

public func groupDocuments(_ docs: [DocView], _ now: CivilDate) -> [DocGroup: [DocView]] {
    let soon = addDays(now, EXPIRING_DAYS)
    var out: [DocGroup: [DocView]] = [.expiring: [], .held: [], .missing: []]
    for d in docs {
        if !d.held { out[.missing]!.append(d) }
        else if d.clash != nil || (d.expiresOn.map { $0 <= soon } ?? false) { out[.expiring]!.append(d) }
        else { out[.held]!.append(d) }
    }
    let byExpiry: (DocView, DocView) -> Bool = { ($0.expiresOn ?? "9999") < ($1.expiresOn ?? "9999") }
    out[.expiring]!.sort(by: byExpiry)
    out[.held]!.sort(by: byExpiry)
    out[.missing]!.sort { ($0.neededBy?.startBy ?? "9999") < ($1.neededBy?.startBy ?? "9999") }
    return out
}
