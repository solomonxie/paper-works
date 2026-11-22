import Foundation
import Observation
import UIKit
import PaperWorksCore

struct Toast: Equatable, Identifiable {
    var id: Int
    var message: String
    var undoable: Bool
}

struct UndoSnapshot { var plan: Plan; var moves: Moves; var toolPlans: [ToolPlan]? = nil }

/// The board on screen: one person's dates, plans, steps and documents.
struct Mine {
    var person: Person
    var anchors: [Anchor]
    var tracks: [Track]
    var instances: [StepInstance]
    var documents: [DocumentRecord]
    /// Country and province: set on the person, or inferred from their events.
    var `where`: Where
    var view: PlanView
}

struct LastChange: Equatable { var cause: String; var detail: String?; var person: String }

/// What iOS currently holds for us (src/state/reminders.ts).
struct ReminderState: Equatable {
    var permission: Permission = .undetermined
    var queued = 0
    var wanted = 0
    var through: CivilDate?
    var calendarDenied = false
}

struct BackupState: Equatable {
    var lastLocal: String?
    var localCount = 0
    var lastICloud: String?
    var icloudStatus: ICloudStatus?
    var error: String?
}

enum RelatedPerson: String { case child, partner, parent }

@MainActor @Observable
final class AppModel {
    // MARK: state (src/state/store.ts)
    var ready = false
    var lastChange: LastChange?
    var mine: Mine
    var now: CivilDate
    var plan: Plan = EMPTY_PLAN
    var settings: Settings = DEFAULT_SETTINGS
    var moves: Moves = [:]
    var playbooks: [Playbook] = bundledPlaybooks
    var view = PlanView()
    var toast: Toast?
    var undoSnapshot: UndoSnapshot?

    // MARK: navigation, demo, services
    var path: [Route] = []
    var demoOn = false
    var demoSwitching = false
    var reminderState = ReminderState()
    var backups = BackupState()
    let storeRegion: String

    @ObservationIgnored private var repo: Repository?
    @ObservationIgnored private var realRepo: Repository?
    @ObservationIgnored private var demoRepo: Repository?
    @ObservationIgnored private let flags = Flags()
    @ObservationIgnored private var toastSeq = 0
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var backupTask: Task<Void, Never>?
    @ObservationIgnored private var writing: Task<Void, Never> = Task {}
    @ObservationIgnored private var autoBackup = false
    @ObservationIgnored private var pendingRestore = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var qa: String?

    init() {
        let today = PaperWorksCore.today()
        now = today
        mine = Mine(person: ME_PERSON, anchors: [], tracks: [], instances: [], documents: [],
                    where: Where(), view: PlanView())
        storeRegion = (Bundle.main.object(forInfoDictionaryKey: "AppStoreRegion") as? String) == "cn" ? "cn" : "us"
        apply(derive(EMPTY_PLAN, today, ME))
    }

    // MARK: derive

    private struct Derived { var playbooks: [Playbook]; var view: PlanView; var mine: Mine }

    private func derive(_ plan: Plan, _ now: CivilDate, _ personId: String) -> Derived {
        let userIds = Set(plan.playbooks.map(\.id))
        let all = bundledPlaybooks.filter { !userIds.contains($0.id) } + plan.playbooks
        let person = plan.people.first { $0.id == personId } ?? plan.people.first ?? ME_PERSON
        let scoped = scopeTo(person.id, plan)
        return Derived(
            playbooks: all,
            view: planView(all, plan.tracks, plan.anchors, plan.instances, now),
            mine: Mine(person: person, anchors: scoped.anchors, tracks: scoped.tracks, instances: scoped.instances,
                       documents: scoped.documents, where: livesIn(scoped.anchors, now),
                       view: planView(all, scoped.tracks, scoped.anchors, scoped.instances, now)))
    }

    private func apply(_ d: Derived) { playbooks = d.playbooks; view = d.view; mine = d.mine }

    // MARK: persistence

    private func persist() {
        var stored = Stored(plan: plan, settings: settings, moves: moves)
        stored.plan = plan
        do { try repo?.save(stored) } catch { print("save failed", error) }
    }

    private static let relabeled = [
        "Migrated to a country": "Relocated to a country",
        "Lodge a visa application": "Apply for permanent residence",
        "Visa granted": "Permit or visa granted",
    ]
    private static let renamed = [
        "pregnancy-ca": "pregnancy-on", "newborn-ca": "newborn-on", "early-years-ca": "early-years-on",
        "coming-of-age-ca": "coming-of-age-on", "retirement-ca": "retirement-on",
    ]

    fileprivate func load(_ repository: Repository) {
        repo = repository
        let stored = (try? repository.load()) ?? nil
        var next = EMPTY_PLAN
        if let stored {
            var tracks = stored.tracks
            for i in tracks.indices { tracks[i].playbookId = Self.renamed[tracks[i].playbookId] ?? tracks[i].playbookId }
            var anchors = stored.anchors
            for i in anchors.indices { anchors[i].label = Self.relabeled[anchors[i].label] ?? anchors[i].label }
            next = Plan(people: stored.people.isEmpty ? [ME_PERSON] : stored.people, anchors: anchors,
                        playbooks: stored.playbooks, tracks: tracks,
                        instances: withNewSteps(tracks, stored.instances, stored.playbooks),
                        documents: stored.documents)
        }
        let today = PaperWorksCore.today()
        let saved = stored?.settings ?? DEFAULT_SETTINGS
        var s = saved
        if !next.people.contains(where: { $0.id == saved.personId }) { s.personId = ME }
        ready = true
        now = today
        plan = next
        settings = s
        settings = migratedNames(settings)
        Haptics.enabled = settings.haptics
        moves = stored?.moves ?? [:]
        apply(derive(next, today, s.personId))
        toast = nil
        undoSnapshot = nil
        lastChange = nil
        if autoBackup { scheduleBackup(after: Self.settle) }
        scheduleSync()
    }

    private func newId() -> String {
        String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
            + String((0..<5).map { _ in "0123456789abcdefghijklmnopqrstuvwxyz".randomElement()! })
    }

    private func instanceId(_ trackId: String, _ stepId: String) -> String { "\(trackId):\(stepId)" }

    private func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    private func instancesFor(_ track: Track, _ playbook: Playbook) -> [StepInstance] {
        (playbook.steps + (track.extraSteps ?? [])).map {
            StepInstance(id: instanceId(track.id, $0.id), trackId: track.id, stepId: $0.id)
        }
    }

    /// Steps a shipped plan gained after it was attached get their own instance.
    private func withNewSteps(_ tracks: [Track], _ instances: [StepInstance], _ user: [Playbook]) -> [StepInstance] {
        let have = Set(instances.map(\.id))
        let all = bundledPlaybooks + user
        let missing = tracks.flatMap { t -> [StepInstance] in
            guard let pb = all.first(where: { $0.id == t.playbookId }) else { return [] }
            return instancesFor(t, pb).filter { !have.contains($0.id) }
        }
        return missing.isEmpty ? instances : instances + missing
    }

    private func titleOf(_ id: String) -> String {
        view.steps.first { $0.scheduled.instanceId == id }?.scheduled.title ?? "Step"
    }

    private func updateInstance(_ id: String, _ patch: (inout StepInstance) -> Void) -> Plan {
        var p = plan
        if let i = p.instances.firstIndex(where: { $0.id == id }) { patch(&p.instances[i]) }
        return p
    }

    private func showToast(_ message: String, undoable: Bool) {
        toastSeq += 1
        toast = Toast(id: toastSeq, message: message, undoable: undoable)
    }

    /// Every plan change goes through here: reflow, record what moved, persist.
    private func commit(_ next: Plan, cause: String, exclude: [String] = [],
                        toast makeToast: ((_ moved: Int, _ direction: Delta) -> String?)? = nil) {
        let d = derive(next, now, settings.personId)
        let summary = summarize(view.steps.map(\.scheduled), d.view.steps.map(\.scheduled), exclude)
        let message: String? = makeToast.map { $0(summary.moved, summary.direction) }
            ?? (summary.moved > 0 ? "\(plural(summary.moved, "step")) moved \(summary.direction.rawValue)." : nil)

        let newMoves = recordMoves(moves, view.steps.map(\.scheduled), d.view.steps.map(\.scheduled), cause, now, exclude)
        undoSnapshot = UndoSnapshot(plan: plan, moves: moves)
        lastChange = LastChange(cause: cause, detail: message, person: mine.person.name)
        plan = next
        apply(d)
        moves = newMoves
        if let message { showToast(message, undoable: true) }
        persist()
        afterPlanChange()
    }

    // MARK: day, toast, undo

    /// Day rolled over while the app slept.
    func refreshToday() {
        let today = PaperWorksCore.today()
        if today == now { return }
        now = today
        apply(derive(plan, today, settings.personId))
    }

    func dismissToast() { toast = nil }

    func undo() {
        guard let snap = undoSnapshot else { return }
        let cause = lastChange?.cause
        plan = snap.plan
        moves = snap.moves
        if let tp = snap.toolPlans { settings.toolPlans = tp }
        apply(derive(snap.plan, now, settings.personId))
        undoSnapshot = nil
        showToast("Undone.", undoable: false)
        lastChange = LastChange(cause: "Undone", detail: cause, person: mine.person.name)
        persist()
        afterPlanChange()
    }

    // MARK: anchors

    /// Empty `anchor.id` makes a new event. `withName` on a spouse or child event links that person:
    /// found by name or created, and given the same event on their own board.
    @discardableResult
    func saveAnchor(_ anchor: Anchor, attach: [String] = [], withName: String? = nil) -> String {
        let existing = plan.anchors.first { $0.id == anchor.id && !anchor.id.isEmpty }
        let personId = anchor.personId ?? existing?.personId ?? settings.personId
        var saved = anchor
        saved.id = anchor.id.isEmpty ? newId() : anchor.id
        saved.personId = personId
        saved.linkId = anchor.linkId ?? existing?.linkId
        saved.withPersonId = anchor.withPersonId ?? existing?.withPersonId
        var people = plan.people
        var anchors = plan.anchors

        let name = withName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLinkedKind(saved.kind), let name, !name.isEmpty {
            var other = people.first { $0.id != personId && $0.name.lowercased() == name.lowercased() }
            if other == nil {
                other = Person(id: newId(), name: name)
                people.append(other!)
            }
            let o = other!
            saved.withPersonId = o.id
            saved.place = o.name
            saved.linkId = saved.linkId ?? newId()
            let ownName = people.first { $0.id == personId }?.name ?? "Me"
            let mirrorKind = LINKED_KINDS[saved.kind]
            let mirror = anchors.first {
                $0.linkId == saved.linkId && $0.id != saved.id && $0.kind == mirrorKind
                    && (mirrorKind == "born" || ownerOf($0) != personId)
            }
            let next = mirrorOf(saved, id: mirror?.id ?? newId(), otherId: o.id, ownName: ownName)
            if let mirror {
                anchors = anchors.map { a in
                    guard a.id == mirror.id else { return a }
                    var m = next
                    m.place = next.place ?? a.place
                    return m
                }
            } else {
                anchors.append(next)
            }
        } else if let linkId = saved.linkId {
            anchors = anchors.map { a in
                guard a.linkId == linkId, a.id != saved.id else { return a }
                var c = a
                c.date = saved.date; c.precision = saved.precision; c.end = saved.end; c.location = saved.location
                return c
            }
        }
        if existing != nil { anchors = anchors.map { $0.id == saved.id ? saved : $0 } } else { anchors.append(saved) }

        var moved = Dictionary(uniqueKeysWithValues: anchors.filter { $0.linkId != nil && $0.linkId == saved.linkId }.map { ($0.id, $0) })
        moved[saved.id] = saved
        var tracks = plan.tracks.map { t -> Track in
            guard let aid = t.anchorId, let a = moved[aid] else { return t }
            var c = t
            let f = fromAnchor(a)
            c.anchorEventDate = f.anchorEventDate; c.anchorEnd = f.anchorEnd; c.purpose = f.purpose
            return c
        }
        var instances = plan.instances
        for playbookId in attach {
            guard let playbook = playbooks.first(where: { $0.id == playbookId }),
                  let on = countsFrom(playbook, saved, anchors) else { continue }
            let f = fromAnchor(on)
            let track = Track(id: newId(), playbookId: playbookId, personId: ownerOf(on), anchorId: on.id,
                              anchorEventDate: f.anchorEventDate, anchorEnd: f.anchorEnd, purpose: f.purpose)
            tracks.append(track)
            instances += instancesFor(track, playbook)
        }

        var next = plan
        next.people = people; next.anchors = anchors; next.tracks = tracks; next.instances = instances
        commit(next, cause: "\(saved.label) moved") { moved, _ in
            moved > 0 ? "\(self.plural(moved, "step")) rescheduled." : nil
        }
        return saved.id
    }

    /// Takes the other person's copy of a linked event with it; the person stays.
    func deleteAnchor(_ id: String) {
        let linkId = plan.anchors.first { $0.id == id }?.linkId
        let ids = Set(plan.anchors.filter { $0.id == id || (linkId != nil && $0.linkId == linkId) }.map(\.id))
        let gone = Set(plan.tracks.filter { $0.anchorId.map(ids.contains) ?? false }.map(\.id))
        var next = plan
        next.anchors = plan.anchors.filter { !ids.contains($0.id) }
        next.tracks = plan.tracks.filter { !gone.contains($0.id) }
        next.instances = plan.instances.filter { !gone.contains($0.trackId) }
        commit(next, cause: "An event was deleted") { _, _ in "Event deleted." }
    }

    // MARK: tool plans

    var mineToolPlans: [ToolPlan] { settings.toolPlans.filter { ($0.personId ?? ME) == mine.person.id } }

    func toolPlans(_ kind: PlanKind) -> [ToolPlan] { mineToolPlans.filter { $0.kind == kind } }

    func toolPlan(_ kind: PlanKind, anchorId: String?) -> ToolPlan? {
        anchorId == nil ? nil : mineToolPlans.first { $0.kind == kind && $0.anchorId == anchorId }
    }

    func toolPlanTitle(_ tp: ToolPlan) -> String { PaperWorksCore.toolPlanTitle(tp, in: mineToolPlans, anchors: plan.anchors) }

    func eventSubtitle(_ tp: ToolPlan) -> String? { plan.anchors.first { $0.id == tp.anchorId }.map(eventLabel) }

    @discardableResult
    func addToolPlan(_ kind: PlanKind, anchorId: String? = nil) -> String? {
        guard let info = toolPlanKind(kind) else { return nil }
        if let have = toolPlan(kind, anchorId: anchorId) { return have.id }
        let owner = plan.anchors.first { $0.id == anchorId }.map(ownerOf) ?? mine.person.id
        let tp = ToolPlan(id: newId(), kind: kind, personId: owner, anchorId: anchorId, addedOn: now)
        undoSnapshot = UndoSnapshot(plan: plan, moves: moves, toolPlans: settings.toolPlans)
        lastChange = LastChange(cause: "\(info.title) added", detail: nil, person: mine.person.name)
        updateSettings { $0.toolPlans.append(tp) }
        showToast("\(info.title) added.", undoable: true)
        return tp.id
    }

    func setToolPlanEvent(_ id: String, anchorId: String?) {
        updateSettings { s in
            guard let i = s.toolPlans.firstIndex(where: { $0.id == id }) else { return }
            s.toolPlans[i].anchorId = anchorId
        }
    }

    func removeToolPlan(_ id: String) {
        guard let tp = settings.toolPlans.first(where: { $0.id == id }) else { return }
        let title = toolPlanKind(tp.kind)?.title ?? "Plan"
        undoSnapshot = UndoSnapshot(plan: plan, moves: moves, toolPlans: settings.toolPlans)
        lastChange = LastChange(cause: "\(title) removed", detail: nil, person: mine.person.name)
        updateSettings { $0.toolPlans.removeAll { $0.id == id } }
        showToast("\(title) removed.", undoable: true)
    }

    func names(for planId: String) -> NameState { settings.toolPlans.first { $0.id == planId }?.names ?? DEFAULT_NAMES }

    func saveNames(_ n: NameState, planId: String) {
        updateSettings { s in
            guard let i = s.toolPlans.firstIndex(where: { $0.id == planId }) else { return }
            s.toolPlans[i].names = n
        }
    }

    func migratedNames(_ s: Settings) -> Settings {
        migrateNames(s, owner: ME, newId: newId, today: PaperWorksCore.today())
    }

    // MARK: tracks

    @discardableResult
    func attachTrack(_ playbookId: String, _ anchorId: String) -> String? {
        guard let playbook = playbooks.first(where: { $0.id == playbookId }),
              let anchor = plan.anchors.first(where: { $0.id == anchorId }) else { return nil }
        let f = fromAnchor(anchor)
        let track = Track(id: newId(), playbookId: playbookId, personId: ownerOf(anchor), anchorId: anchorId,
                          anchorEventDate: f.anchorEventDate, anchorEnd: f.anchorEnd, purpose: f.purpose)
        var next = plan
        next.tracks.append(track)
        next.instances += instancesFor(track, playbook)
        commit(next, cause: "\(playbook.title) attached") { _, _ in
            "\(playbook.title) attached · \(self.plural(playbook.steps.count, "step"))."
        }
        return track.id
    }

    func reanchorTrack(_ trackId: String, _ anchorId: String) {
        guard let anchor = plan.anchors.first(where: { $0.id == anchorId }) else { return }
        let f = fromAnchor(anchor)
        var next = plan
        next.tracks = plan.tracks.map { t in
            guard t.id == trackId else { return t }
            var c = t
            c.anchorId = anchorId; c.anchorEventDate = f.anchorEventDate; c.anchorEnd = f.anchorEnd; c.purpose = f.purpose
            return c
        }
        commit(next, cause: "Now anchored on \(anchor.label)")
    }

    func detachTrack(_ trackId: String) {
        let track = plan.tracks.first { $0.id == trackId }
        let title = playbooks.first { $0.id == track?.playbookId }?.title ?? "Plan"
        var next = plan
        next.tracks = plan.tracks.filter { $0.id != trackId }
        next.instances = plan.instances.filter { $0.trackId != trackId }
        commit(next, cause: "\(title) detached") { _, _ in "\(title) detached." }
    }

    @discardableResult
    func planRedo(_ trackId: String, _ sourceStepId: String, _ consumerStepId: String) -> String? {
        guard let track = plan.tracks.first(where: { $0.id == trackId }),
              let playbook = playbooks.first(where: { $0.id == track.playbookId }) else { return nil }
        let anchored = anchoredTrack(track, plan.anchors)
        let scheduled = view.steps.filter { $0.trackId == trackId }.map(\.scheduled)
        var saved = PaperWorksCore.planRedo(playbook, anchored, sourceStepId, consumerStepId, scheduled)
        guard let redo = saved.extraSteps?.last, saved != anchored else { return nil }
        saved.anchorEventDate = track.anchorEventDate
        let base = redo.title.replacingOccurrences(of: " (redo)", with: "")
        var next = plan
        next.tracks = plan.tracks.map { $0.id == trackId ? saved : $0 }
        next.instances.append(StepInstance(id: instanceId(trackId, redo.id), trackId: trackId, stepId: redo.id))
        commit(next, cause: "Redo of \(base) planned") { _, _ in "Redo planned: \(base)." }
        return instanceId(trackId, redo.id)
    }

    // MARK: steps

    func markDone(_ id: String, on: CivilDate? = nil) {
        let day = on ?? now
        let next = updateInstance(id) { $0.status = .done; $0.completedOn = day; $0.snoozedUntil = nil }
        commit(next, cause: "\(titleOf(id)) done", exclude: [id]) { moved, direction in
            moved == 0 ? "Done." : "Done. \(self.plural(moved, "later step")) moved \(direction.rawValue)."
        }
    }

    func reopen(_ id: String) {
        commit(updateInstance(id) { $0.status = .pending; $0.completedOn = nil },
               cause: "\(titleOf(id)) reopened", exclude: [id])
    }

    func snooze(_ id: String, until: CivilDate) {
        commit(updateInstance(id) { $0.status = .snoozed; $0.snoozedUntil = until },
               cause: "\(titleOf(id)) snoozed", exclude: [id]) { _, _ in "Snoozed." }
    }

    func clearSnooze(_ id: String) {
        commit(updateInstance(id) { $0.status = .pending; $0.snoozedUntil = nil },
               cause: "\(titleOf(id)) unsnoozed", exclude: [id])
    }

    func skip(_ id: String) {
        commit(updateInstance(id) { $0.status = .skipped }, cause: "\(titleOf(id)) marked not for me", exclude: [id]) { moved, direction in
            moved == 0 ? "Marked not for me." : "Marked not for me. \(self.plural(moved, "later step")) moved \(direction.rawValue)."
        }
    }

    func restore(_ id: String) {
        commit(updateInstance(id) { $0.status = .pending }, cause: "\(titleOf(id)) restored", exclude: [id])
    }

    func moveDue(_ id: String, _ date: CivilDate?) {
        commit(updateInstance(id) { $0.dueOverride = date }, cause: "\(titleOf(id)) due date moved", exclude: [id])
    }

    func setNote(_ id: String, _ note: String) {
        commit(updateInstance(id) { $0.note = note.isEmpty ? nil : note }, cause: "Note", exclude: [id]) { _, _ in nil }
    }

    func togglePrepare(_ id: String, _ item: String) {
        commit(updateInstance(id) {
            if let i = $0.checkedPrepare.firstIndex(of: item) { $0.checkedPrepare.remove(at: i) } else { $0.checkedPrepare.append(item) }
        }, cause: "Prep", exclude: [id]) { _, _ in nil }
    }

    /// Checking a document also records it as held from today.
    func toggleDocument(_ id: String, _ name: String) {
        let instance = plan.instances.first { $0.id == id }
        let checking = !(instance?.checkedDocuments.contains(name) ?? false)
        var next = updateInstance(id) {
            if checking { $0.checkedDocuments.append(name) } else { $0.checkedDocuments.removeAll { $0 == name } }
        }
        let key = docId(name)
        let personId = mine.person.id
        if checking && !next.documents.contains(where: { $0.id == key && ownerOf($0) == personId }) {
            next.documents.append(DocumentRecord(id: key, name: name, personId: personId, issuedOn: now))
        }
        commit(next, cause: "Document", exclude: [id]) { _, _ in nil }
    }

    // MARK: documents

    func saveDocument(_ doc: DocumentRecord) {
        var saved = doc
        saved.personId = mine.person.id
        let same: (DocumentRecord) -> Bool = { $0.id == doc.id && ownerOf($0) == saved.personId! }
        var next = plan
        if plan.documents.contains(where: same) {
            next.documents = plan.documents.map { same($0) ? saved : $0 }
        } else {
            next.documents.append(saved)
        }
        commit(next, cause: "\(doc.name) updated") { _, _ in nil }
    }

    func forgetDocument(_ id: String) {
        let owner = mine.person.id
        let same: (DocumentRecord) -> Bool = { $0.id == id && ownerOf($0) == owner }
        let name = plan.documents.first(where: same)?.name
        let own = Set(mine.tracks.map(\.id))
        var next = plan
        next.documents = plan.documents.filter { !same($0) }
        next.instances = plan.instances.map { i in
            guard own.contains(i.trackId) else { return i }
            var c = i
            c.checkedDocuments = i.checkedDocuments.filter { docId($0) != id }
            return c
        }
        commit(next, cause: "Document forgotten") { _, _ in "\(name ?? "Document") forgotten." }
    }

    // MARK: playbooks and backup

    func savePlaybook(_ playbook: Playbook) {
        var next = plan
        if plan.playbooks.contains(where: { $0.id == playbook.id }) {
            next.playbooks = plan.playbooks.map { $0.id == playbook.id ? playbook : $0 }
        } else {
            next.playbooks.append(playbook)
        }
        commit(next, cause: "\(playbook.title) updated")
    }

    @discardableResult
    func duplicatePlaybook(_ id: String) -> String? {
        guard var copy = playbooks.first(where: { $0.id == id }) else { return nil }
        copy.id = "\(copy.id)-copy-\(newId())"
        copy.title = "\(copy.title) (copy)"
        savePlaybook(copy)
        return copy.id
    }

    /// Back to Me if the person on screen isn't in the new plan.
    func replacePlan(_ new: Plan) {
        var next = new
        if next.people.isEmpty { next.people = [ME_PERSON] }
        if !next.people.contains(where: { $0.id == settings.personId }) { settings.personId = ME }
        commit(next, cause: "Backup imported") { _, _ in "Plan replaced from the backup." }
    }

    func updateSettings(_ patch: (inout Settings) -> Void) {
        let before = settings
        patch(&settings)
        Haptics.enabled = settings.haptics
        persist()
        if before.calendarMirror && !settings.calendarMirror && !demoOn { Task { await CalendarMirror.remove() } }
        if autoBackup { scheduleBackup(after: settings.icloudBackup && !before.icloudBackup ? 0 : Self.settle) }
        scheduleSync()
    }

    // MARK: people

    func switchPerson(_ personId: String) {
        settings.personId = personId
        apply(derive(plan, now, personId))
        persist()
        scheduleSync()
    }

    /// A board of their own, not tied to anyone.
    @discardableResult
    func addPerson(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let person = Person(id: newId(), name: trimmed.isEmpty ? "Someone" : trimmed)
        var next = plan
        next.people.append(person)
        commit(next, cause: "\(person.name) added") { _, _ in nil }
        switchPerson(person.id)
        return person.id
    }

    /// A child, partner or parent of whoever is on screen, joined by the event that ties them.
    @discardableResult
    func linkPerson(_ name: String, _ relation: RelatedPerson, _ date: CivilDate, _ precision: DatePrecision) -> String? {
        if relation == .parent { return linkParent(name, date, precision) }
        let child = relation == .child
        let id = saveAnchor(Anchor(id: "", kind: child ? "child-born" : "married", label: child ? "Child born" : "Married",
                                   date: date, precision: precision), withName: name)
        return plan.anchors.first { $0.id == id }?.withPersonId
    }

    private func linkParent(_ name: String, _ date: CivilDate, _ precision: DatePrecision) -> String {
        let childId = mine.person.id
        var anchors = plan.anchors
        var people = plan.people
        var born = mine.anchors.first { $0.kind == "born" }
        let linkId = born?.linkId ?? newId()
        if let b = born {
            anchors = anchors.map { $0.id == b.id ? { var c = $0; c.linkId = linkId; return c }($0) : $0 }
            born!.linkId = linkId
        } else {
            born = Anchor(id: newId(), kind: "born", label: "Born", date: date, precision: precision, personId: childId, linkId: linkId)
            anchors.append(born!)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var parent = people.first { $0.id != childId && $0.name.lowercased() == trimmed.lowercased() }
        if parent == nil {
            parent = Person(id: newId(), name: trimmed)
            people.append(parent!)
        }
        let p = parent!
        if !anchors.contains(where: { $0.linkId == linkId && ownerOf($0) == p.id }) {
            anchors.append(Anchor(id: newId(), kind: "child-born", label: "Child born", place: mine.person.name,
                                  date: born!.date, precision: born!.precision, personId: p.id,
                                  withPersonId: childId, linkId: linkId))
        }
        var next = plan
        next.people = people; next.anchors = anchors
        commit(next, cause: "\(p.name) linked") { _, _ in nil }
        return p.id
    }

    /// Swap a plan for its twin in another province, on the same date; progress doesn't carry over.
    @discardableResult
    func switchTrack(_ trackId: String, _ playbookId: String) -> String? {
        guard let track = plan.tracks.first(where: { $0.id == trackId }),
              let playbook = playbooks.first(where: { $0.id == playbookId }) else { return nil }
        var new = track
        new.id = newId(); new.playbookId = playbookId; new.extraSteps = nil; new.extraDependsOn = nil
        var next = plan
        next.tracks = plan.tracks.map { $0.id == trackId ? new : $0 }
        next.instances = plan.instances.filter { $0.trackId != trackId } + instancesFor(new, playbook)
        commit(next, cause: "Switched to \(playbook.title)") { _, _ in "Switched to \(playbook.title)." }
        return new.id
    }

    func renamePerson(_ id: String, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        var next = plan
        next.people = plan.people.map { p in var c = p; if p.id == id { c.name = trimmed }; return c }
        commit(next, cause: "Renamed") { _, _ in nil }
    }

    /// Their board goes; events on other boards stay, no longer linked.
    func removePerson(_ id: String) {
        if id == ME { return }
        let name = plan.people.first { $0.id == id }?.name ?? "Person"
        let gone = Set(plan.tracks.filter { t in
            ownerOf(t.personId) == id || plan.anchors.contains { $0.id == t.anchorId && ownerOf($0) == id }
        }.map(\.id))
        if settings.personId == id { switchPerson(ME) }
        var next = plan
        next.people = plan.people.filter { $0.id != id }
        next.anchors = plan.anchors.filter { ownerOf($0) != id }.map { a in
            guard a.withPersonId == id else { return a }
            var c = a; c.withPersonId = nil; c.linkId = nil
            return c
        }
        next.tracks = plan.tracks.filter { !gone.contains($0.id) }
        next.instances = plan.instances.filter { !gone.contains($0.trackId) }
        next.documents = plan.documents.filter { ownerOf($0) != id }
        commit(next, cause: "\(name) removed") { _, _ in "\(name) removed." }
    }

    // MARK: navigation

    func push(_ route: Route) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }

    /// A notification's target: "radar" or "step:<instanceId>". A step opens on its owner's board.
    func openTarget(_ target: String) {
        let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
        let id = parts.count > 1 ? parts[1] : nil
        if let id, let track = plan.tracks.first(where: { id.hasPrefix("\($0.id):") }) {
            switchPerson(trackOwner(track, plan.anchors))
        }
        path = parts.first == "step" && id != nil ? [.step(instanceId: id!)] : []
    }

    // MARK: startup and demo (App.tsx, src/state/demo.ts)

    func start() async {
        if started { return }
        started = true
        let env = ProcessInfo.processInfo.environment
        qa = env["PW_QA"]
        if qa != nil {
            load(Repository(name: "qa.db"))
            qaSeed()
        } else {
            demoOn = flags.get("demo") == "1"
            if demoOn {
                BackupStorage.demoMode = true
                openDemo()
            } else {
                let restored = await restoreFromICloud()
                load(realStore())
                if restored { showToast("Restored from iCloud", undoable: false) }
                if flags.get("icloudDefaultOn") == nil {
                    if !restored && !settings.icloudBackup { updateSettings { $0.icloudBackup = true } }
                    try? flags.set("icloudDefaultOn", "1")
                }
            }
        }
        if qa == nil { startAutoBackup() }
        await syncNow()
        takeOpenedTarget()
    }

    func becameActive() {
        refreshToday()
        scheduleSync()
        takeOpenedTarget()
    }

    private func takeOpenedTarget() {
        if let t = Notifications.shared.takeOpened() { openTarget(t) }
    }

    /// Fresh install or after deletion: no local rows. Local data is never overwritten.
    private func restoreFromICloud() async -> Bool {
        let store = realStore()
        guard ((try? store.load()) ?? nil) == nil, DEFAULT_SETTINGS.icloudBackup else { return false }
        guard let text = await ICloudBackup.newestSnapshot(timeout: 8),
              case .ok(let restoredPlan, let restoredSettings, let restoredMoves) = parseSnapshot(text),
              (try? store.save(Stored(plan: restoredPlan, settings: migratedNames(restoredSettings ?? DEFAULT_SETTINGS),
                                      moves: restoredMoves ?? [:]))) != nil else {
            pendingRestore = true
            return false
        }
        await ICloudBackup.restoreScans(to: Files.scansURL, timeout: 20)
        return true
    }

    private func realStore() -> Repository { realRepo ?? { let r = Repository(); realRepo = r; return r }() }
    private func demoStore() -> Repository { demoRepo ?? { let r = Repository(name: "demo.db"); demoRepo = r; return r }() }

    private func openDemo() {
        load(demoStore())
        if plan.anchors.isEmpty { seedDemo() }
    }

    private func seedDemo() {
        updateSettings { $0.firstRunDone = true; $0.icloudBackup = true; $0.askedNotifications = true }
        seedSample()
    }

    private func qaSeed() {
        let spec = (qa ?? "").split(separator: "@").first.map(String.init) ?? ""
        if spec == "sample" {
            replacePlan(EMPTY_PLAN)
            updateSettings { $0.firstRunDone = true }
            seedSample()
        } else if spec == "empty" {
            replacePlan(EMPTY_PLAN)
            updateSettings { $0.firstRunDone = false }
        }
    }

    /// Real <-> demo in place; demo data never reaches iOS reminders, calendar or the real backup files.
    func setDemo(_ on: Bool) async {
        if demoSwitching || on == demoOn { return }
        demoSwitching = true
        defer { demoSwitching = false }
        await writing.value
        if on {
            BackupStorage.demoMode = true
            openDemo()
        } else {
            load(realStore())
            await writing.value
            BackupStorage.demoMode = false
            await syncNow()
        }
        refreshBackupState()
        demoOn = on
        do { try flags.set("demo", on ? "1" : "0") } catch { print("demo flag not saved", error) }
    }

    /// Back to the plan in `demo/`, as first installed.
    func resetDemo() {
        if !demoOn { return }
        replacePlan(EMPTY_PLAN)
        seedDemo()
    }

    /// Replays Core's DEMO_* data through the actions into whatever store is open.
    func seedSample() {
        let today = now
        for e in DEMO_EVENTS {
            let a = Anchor(id: "", kind: e.kind, label: e.label, place: e.place, location: e.location,
                           date: demoDate(e.date, today), precision: e.precision, note: e.note, personId: ME)
            saveAnchor(a, attach: e.plans, withName: e.with)
        }
        for item in DEMO_PERSON_PLANS {
            let id = plan.people.first { $0.name == item.person }?.id
            if let born = plan.anchors.first(where: { $0.personId == id && $0.kind == "born" }) {
                item.plans.forEach { attachTrack($0, born.id) }
            }
        }
        for s in view.steps where s.scheduled.dueBy < today && s.scheduled.status == .pending {
            markDone(s.scheduled.instanceId, on: s.scheduled.dueBy)
        }
        let steps = view.steps
        for (title, on) in DEMO_DONE {
            if let s = steps.first(where: { Self.matches(title, $0.scheduled.title) && $0.scheduled.status == .pending }) {
                markDone(s.scheduled.instanceId, on: demoDate(on, today))
            }
        }
        for title in DEMO_GATHERED {
            if let s = steps.first(where: { Self.matches(title, $0.scheduled.title) }), let d = s.template.documents.first {
                toggleDocument(s.scheduled.instanceId, d)
            }
        }
        for d in DEMO_DOCUMENTS {
            let owner = d.person.map { name in plan.people.first { $0.name == name }?.id } ?? ME
            guard let owner else { continue }
            if mine.person.id != owner { switchPerson(owner) }
            saveDocument(d.record(owner: owner, now: today))
        }
        switchPerson(ME)
        dismissToast()
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: sync (src/state/sync.ts)

    private func afterPlanChange() {
        scheduleSync()
        guard autoBackup else { return }
        if let c = lastChange { logChange(c.person, [c.cause, c.detail].compactMap { $0 }.joined(separator: " · ")) }
        scheduleBackup(after: Self.settle)
    }

    private func scheduleSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            await self?.syncNow()
        }
    }

    /// Keeps what iOS holds (reminders, the optional calendar) in step with the plan.
    func syncNow() async {
        guard ready else { return }
        let steps = view.steps
        let open = steps.filter { isOpen($0.scheduled) }
        if !settings.askedNotifications && !open.isEmpty {
            updateSettings { $0.askedNotifications = true }
            if await Notifications.shared.status() == .undetermined { _ = await Notifications.shared.request() }
        }
        let permission = await Notifications.shared.status()
        let q = buildQueue(steps, now, QueueOptions(
            leadDays: settings.leadDays, hour: 9,
            digest: settings.digestOn ? (settings.digestWeekday, settings.digestHour) : nil))
        if permission == .granted {
            let queued = demoOn ? q.items.count : await Notifications.shared.replaceQueue(q.items)
            reminderState.queued = queued
            reminderState.through = q.through
        } else {
            reminderState.queued = 0
            reminderState.through = nil
        }
        reminderState.permission = permission
        reminderState.wanted = q.wanted

        if settings.calendarMirror {
            let entries = open.map {
                DatedEntry(title: "Start: \($0.scheduled.title)", date: $0.scheduled.startBy,
                           notes: "\($0.playbook.title) · due \(formatShort($0.scheduled.dueBy)). From Paper Works — a plan, not advice.")
            }
            let n = demoOn ? entries.count : ((try? await CalendarMirror.sync(entries)) ?? 0)
            reminderState.calendarDenied = n < 0
        }
    }

    // MARK: autobackup (src/state/autobackup.ts)

    private func startAutoBackup() {
        autoBackup = true
        refreshBackupState()
    }

    private static let settle = 2.0

    /// Flushes a pending snapshot before iOS suspends the app.
    func wentToBackground() {
        guard autoBackup, ready else { return }
        backupTask?.cancel()
        enqueueBackup(plan: plan)
        let app = UIApplication.shared
        var id = UIBackgroundTaskIdentifier.invalid
        id = app.beginBackgroundTask { app.endBackgroundTask(id) }
        let pending = writing
        Task { await pending.value; app.endBackgroundTask(id) }
    }

    func backupNow(tag: String? = nil) async {
        enqueueBackup(plan: plan, tag: tag)
        await writing.value
    }

    private func enqueueBackup(plan: Plan, tag: String? = nil) {
        let prev = writing
        writing = Task { [weak self] in
            await prev.value
            await self?.writeBackup(plan, tag)
        }
    }

    private func writeBackup(_ plan: Plan, _ tag: String?) async {
        let at = Date()
        let day = PaperWorksCore.today(at)
        let text = serializeStored(Stored(plan: plan, settings: settings, moves: moves), day)
        do {
            try await BackupStorage.writeBackup(snapshotName(at, tag), text)
            let names = await BackupStorage.listBackups()
            let gone = snapshotsToPrune(names, day)
            if !gone.isEmpty { await BackupStorage.deleteBackups(gone) }
            backups.lastLocal = "\(day)T\(Self.clock(at, seconds: false))"
            backups.localCount = names.count - gone.count
            backups.error = nil
        } catch {
            backups.error = "Couldn't write a snapshot: \(error.localizedDescription)"
        }
        if settings.icloudBackup {
            let status = await BackupStorage.icloudStatus()
            backups.icloudStatus = status
            if pendingRestore && status == .available && (plan.anchors.isEmpty && plan.tracks.isEmpty && plan.documents.isEmpty) {
                return
            }
            if status == .available {
                pendingRestore = false
                do {
                    try await BackupStorage.icloudWriteSnapshot(text, day: day)
                    backups.lastICloud = "\(day)T\(Self.clock(at, seconds: true))"
                } catch {
                    backups.error = "Couldn't write to iCloud: \(error.localizedDescription)"
                }
            }
        }
    }

    private static func clock(_ d: Date, seconds: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = seconds ? "HH:mm:ss" : "HH:mm"
        return f.string(from: d)
    }

    /// Rapid edits settle into one write of today's copy.
    private func scheduleBackup(after seconds: Double) {
        backupTask?.cancel()
        backupTask = Task { [weak self] in
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            if Task.isCancelled { return }
            guard let self else { return }
            self.enqueueBackup(plan: self.plan)
        }
    }

    private func logChange(_ who: String, _ what: String) {
        let at = Date()
        let prev = writing
        writing = Task { [weak self] in
            await prev.value
            do { try await BackupStorage.appendBackup(changeLogName(at), changeLine(at, who, what)) }
            catch { self?.backups.error = "Couldn't add to the change log: \(error.localizedDescription)" }
        }
    }

    /// Re-reads what's on disk, e.g. after switching between the real and the demo plan.
    func refreshBackupState() {
        backups.lastICloud = nil
        backups.error = nil
        Task {
            backups.icloudStatus = await BackupStorage.icloudStatus()
            let names = await BackupStorage.listBackups().filter(isSnapshot).sorted()
            backups.localCount = names.count
            backups.lastLocal = names.last
        }
    }

    /// Permission and queue refresh for the Reminders screen.
    func refreshReminderState() { Task { await syncNow() } }
}
