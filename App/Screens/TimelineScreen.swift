import SwiftUI
import PaperWorksCore

/// The whole app on one page: whose board, their paperwork, their events, their plans, then Settings.
struct TimelineScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var menu = false
    @State private var confirmRemove = false

    private var person: Person { model.mine.person }
    private var isMe: Bool { person.id == ME }

    private struct EventNode: Identifiable {
        var node: TimelineNode
        var noted: Bool
        var place: String?
        var id: String { node.id }
    }

    private var nodes: [EventNode] {
        let m = model.mine
        return timelineNodes(m.anchors, m.tracks, m.view.steps, model.now)
            .filter { $0.source == .anchor }
            .map { n in
                let a = m.anchors.first { $0.id == n.anchorId }
                return EventNode(node: n, noted: !(a?.note ?? "").isEmpty, place: a?.location.map(placeShort))
            }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if menu { menuCard }
                    if model.mine.anchors.isEmpty { firstRun } else { board(proxy) }
                    Card {
                        ListRow("Settings", value: model.demoOn ? "demo data" : nil) { go { model.push(.settings) } }
                    }
                    .padding(.top, Space.xl)
                }
                .padding(.bottom, 120)
            }
        }
        .background(p.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { titleButton } }
        .alert("Remove \(person.name)?", isPresented: $confirmRemove) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { go { model.removePerson(person.id) } }
        } message: { Text("Their events and plans go. Events on other boards stay.") }
    }

    private func go(_ fn: () -> Void) { menu = false; fn() }

    // MARK: header

    private var titleButton: some View {
        Button { menu.toggle() } label: {
            VStack(spacing: 0) {
                Text("Paper Works \(menu ? "▴" : "▾")").font(TypeStyle.headline).foregroundStyle(p.text)
                if !isMe { Text(person.name).font(TypeStyle.caption).foregroundStyle(p.dim).lineLimit(1) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paper Works, showing \(isMe ? "you" : person.name). Switch person")
        .accessibilityValue(menu ? "expanded" : "collapsed")
    }

    private var menuCard: some View {
        Card {
            Rows {
                ForEach(menuPeople(model.plan.people, model.plan.anchors, showing: person.id)) { x in
                    let here = x.id == person.id
                    ListRow("\(here ? "✓ " : "   ")\(x.name)", onPress: { go { model.switchPerson(x.id) } }, chevron: false,
                            accessibilityLabel: "\(x.name)\(here ? ", showing" : "")")
                }
                ListRow("＋ New person") { go { model.push(.person(mode: .new, personId: nil)) } }
                ListRow("Link a person to \(person.name)",
                        detail: "A child, partner or parent, joined by the event that ties you") {
                    go { model.push(.person(mode: .link, personId: nil)) }
                }
                ListRow("Rename \(person.name)") { go { model.push(.person(mode: .rename, personId: person.id)) } }
                if !isMe {
                    ListRow("Remove \(person.name)", onPress: { confirmRemove = true }, chevron: false, tone: .late)
                }
            }
        }
        .padding(.top, Space.sm)
    }

    private var firstRun: some View {
        EmptyState(title: isMe ? "Paper Works" : person.name,
                   message: "Add the event your paperwork is for — a move, a trip, a new baby, a visa — and the forms it needs line up in order.",
                   action: "Add an event") { model.push(.anchorEdit(anchorId: nil, kind: nil)) }
    }

    // MARK: board

    @ViewBuilder private func board(_ proxy: ScrollViewProxy) -> some View {
        let now = model.now
        let steps = model.mine.view.steps
        let open = openSteps(steps)
        let running = open.filter { $0.startBy <= now }.count
        let next = open.filter { $0.startBy > now }.min { $0.startBy < $1.startBy }
        let late = lateSteps(steps, now).count
        let all = nodes
        let upcoming = all.filter { $0.node.date > now }
        let past = all.filter { $0.node.date <= now }.reversed()
        let toPlans = { withAnimation { proxy.scrollTo("plans", anchor: .top) } }

        SectionHeader("Paperwork")
        Card {
            Rows {
                if late > 0 {
                    ListRow("⚠ \(late) step\(late == 1 ? " is" : "s are") late", onPress: toPlans, tone: .late)
                }
                ListRow(stepsLine(running, next.map { diffDays(now, $0.startBy) }, model.mine.tracks.count),
                        onPress: toPlans, tone: model.mine.tracks.isEmpty ? .dim : .normal)
            }
        }
        if !upcoming.isEmpty { eventList("Coming up", upcoming) }
        if !past.isEmpty { eventList("Past", Array(past)) }

        Button("+ Add an event") { model.push(.anchorEdit(anchorId: nil, kind: nil)) }
            .buttonStyle(.pwPlain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.lg).padding(.top, Space.md)

        PlansSection().id("plans")
    }

    private func eventList(_ title: String, _ items: [EventNode]) -> some View {
        VStack(spacing: 0) {
            SectionHeader(title)
            Card {
                Rows {
                    ForEach(items) { e in
                        let n = e.node
                        let detail = [formatPrecise(n.date, n.precision), e.place, n.end.map { formatLasts(n.date, $0) }]
                            .compactMap { $0 }.joined(separator: " · ")
                        ListRow("\(n.label)\(e.noted ? " ✎" : "")", value: n.pendingSteps > 0 ? "\(n.pendingSteps) to do" : nil,
                                detail: detail, onPress: { open(e) }, tone: n.pendingSteps > 0 ? .normal : .dim)
                    }
                }
            }
        }
    }

    private func open(_ e: EventNode) {
        if e.node.source == .anchor && e.node.date <= model.now {
            model.push(.anchorEdit(anchorId: e.node.id, kind: nil))
        } else {
            model.push(.chapter(eventId: e.node.id))
        }
    }

    private func stepsLine(_ running: Int, _ nextIn: Int?, _ tracks: Int) -> String {
        if tracks == 0 { return "No paperwork plans yet" }
        var parts = ["\(running) step\(running == 1 ? "" : "s") running"]
        if let nextIn { parts.append("next starts in \(nextIn)d") }
        return parts.joined(separator: " · ")
    }
}

/// Sep 2024 ───●──── Sep 2029, ● at today.
struct ChapterBar: View {
    let start: CivilDate
    let end: CivilDate?
    let now: CivilDate
    @Environment(\.palette) private var p

    var body: some View {
        let ratio: Double = end.map { e in
            let span = diffDays(start, e)
            return span == 0 ? 0.5 : min(1, max(0, Double(diffDays(start, now)) / Double(span)))
        } ?? 0.5
        HStack(spacing: Space.sm) {
            Text(formatMonth(start)).font(TypeStyle.caption).foregroundStyle(p.dim)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.hairline).frame(height: 2)
                    Capsule().fill(p.accent).frame(width: g.size.width * ratio, height: 2)
                    Circle().fill(p.accent).overlay(Circle().stroke(p.card, lineWidth: 2))
                        .frame(width: 14, height: 14).offset(x: g.size.width * ratio - 7)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
            Text(end.map(formatMonth) ?? "…").font(TypeStyle.caption).foregroundStyle(p.dim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(formatMonth(start)) to \(end.map(formatMonth) ?? "open ended")")
    }
}

// MARK: - Plans

/// Everything ahead for the person on screen, under their timeline.
private struct PlansSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @Environment(\.openURL) private var openURL

    var body: some View {
        let count = model.mine.tracks.count + model.mineToolPlans.count
        let hasPlans = count > 0
        let banner = model.reminderState.permission == .denied && !model.settings.deniedBannerDismissed && hasPlans
        SectionHeader("Plans", count: hasPlans ? count : nil)
        if banner { bannerCard }
        ExpiringDocs()
        RunningPlans()
        FinishedPlans()
        Button(hasPlans ? "+ Add a plan" : "Browse plans") { model.push(.library) }
            .buttonStyle(hasPlans ? .pw(.plain) : .pw(.primary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.lg).padding(.top, Space.md)
    }

    private var bannerCard: some View {
        HStack(spacing: Space.md) {
            Text("Reminders are off, so nothing will warn you.").font(TypeStyle.body).foregroundStyle(p.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Allow") {
                Task {
                    if await Notifications.shared.request() { model.refreshReminderState() }
                    else if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            .font(TypeStyle.label).foregroundStyle(p.accent)
            Button("✕") { model.updateSettings { $0.deniedBannerDismissed = true } }
                .font(TypeStyle.label).foregroundStyle(p.dim).accessibilityLabel("Dismiss")
        }
        .padding(.vertical, Space.md).padding(.horizontal, Space.lg)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(p.lateSoft))
        .padding(.horizontal, Space.lg).padding(.top, Space.md)
    }
}

private struct PlanSummary: Identifiable {
    var track: Track
    var done: Int
    var total: Int
    var next: PlannedStep?
    var anchor: PaperWorksCore.Anchor?
    var playbook: Playbook?
    var id: String { track.id }
}

@MainActor private func summaries(_ model: AppModel) -> [PlanSummary] {
    let m = model.mine
    return m.tracks.map { t in
        let steps = m.view.steps.filter { $0.trackId == t.id }
        let counted = steps.filter { $0.status != .skipped }
        return PlanSummary(
            track: t, done: counted.filter { $0.status == .done }.count, total: counted.count,
            next: steps.filter { isOpen($0.scheduled) }.min { $0.startBy < $1.startBy },
            anchor: m.anchors.first { $0.id == t.anchorId },
            playbook: model.playbooks.first { $0.id == t.playbookId })
    }
}

/// One plan, two lines tall: a type badge, the title with its count, what's next, and a thin bar.
private struct PlanRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let trailing: String
    let subtitle: String
    var warning: String? = nil
    let done: Int
    let total: Int
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.sm) {
                    Text(title).font(TypeStyle.label).foregroundStyle(p.text).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(trailing).font(TypeStyle.caption.weight(.medium)).foregroundStyle(p.dim)
                }
                Text(subtitle).font(TypeStyle.caption).foregroundStyle(p.dim).lineLimit(1)
                if let warning { Text(warning).font(TypeStyle.caption).foregroundStyle(p.warn).lineLimit(1) }
                if total > 0 {
                    Capsule().fill(p.hairline).frame(height: 3)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule().fill(done >= total ? p.done : tint)
                                    .frame(width: g.size.width * min(1, Double(done) / Double(total)))
                            }
                        }
                        .padding(.top, 3)
                }
            }
            Text("›").font(TypeStyle.body).foregroundStyle(p.faint)
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

private struct RunningPlans: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    @State private var changing: String?

    var body: some View {
        let running = summaries(model).filter { $0.done < $0.total || $0.total == 0 }
        let tools = model.mineToolPlans
        if !running.isEmpty || !tools.isEmpty {
            Card {
                Rows {
                    ForEach(tools) { tp in toolRow(tp) }
                    ForEach(running) { x in row(x) }
                }
            }
            .sheet(item: Binding(get: { changing.map { Changing(id: $0) } }, set: { changing = $0?.id })) { c in
                EventPicker(current: model.settings.toolPlans.first { $0.id == c.id }?.anchorId) {
                    model.setToolPlanEvent(c.id, anchorId: $0)
                } onNew: { model.push(.anchorEdit(anchorId: nil, kind: "baby-due")) }
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private struct Changing: Identifiable { let id: String }

    /// A different kind of plan: rose heart badge, "♥ liked" up top, names seen as the bar.
    @ViewBuilder private func toolRow(_ tp: ToolPlan) -> some View {
        if toolPlanKind(tp.kind) != nil {
            let names = model.names(for: tp.id)
            let seen = names.liked.count + names.passed.count
            let next = deck(NAMES, names).first
            Button { model.push(.names(planId: tp.id)) } label: {
                PlanRow(symbol: "heart.fill", tint: nameTint(.f), title: model.toolPlanTitle(tp),
                        trailing: "♥ \(names.liked.count)",
                        subtitle: next.map { "Next: \($0.hanzi ?? $0.name)" } ?? "All seen",
                        done: seen, total: max(seen, fitting(NAMES, names)))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Change event…") { changing = tp.id }
                Button("Remove plan", role: .destructive) { model.removeToolPlan(tp.id) }
            }
        }
    }

    private func row(_ x: PlanSummary) -> some View {
        let m = model.mine
        let misfit: Bool = x.playbook.map { !fits($0, whereFor($0, x.anchor, m.where, m.anchors)) } ?? false
        let place = x.anchor?.place.flatMap { pl in x.playbook?.region?.contains(pl) == true ? nil : pl }
        return Button { model.push(.playbook(playbookId: x.track.playbookId, trackId: x.track.id)) } label: {
            PlanRow(symbol: "doc.text.fill", tint: p.accent,
                    title: (x.playbook?.title ?? "Missing playbook") + (place.map { " · \($0)" } ?? ""),
                    trailing: "\(x.done)/\(x.total)", subtitle: nextLabel(x.next, model.now),
                    warning: misfit ? x.playbook.map { "\(rulesName($0) ?? "") rules · \(whereWhy(x.anchor, m.where))" } : nil,
                    done: x.done, total: x.total)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(x.playbook?.title ?? "Plan"), \(x.done) of \(x.total) done")
    }

    private func nextLabel(_ next: PlannedStep?, _ now: CivilDate) -> String {
        guard let next else { return "Nothing left to start" }
        let when = next.startBy <= now ? "now"
            : next.startBy.prefix(4) == now.prefix(4) ? formatShort(next.startBy) : formatMonth(next.startBy)
        return "Next: \(next.scheduled.title) · \(when)"
    }
}

private struct FinishedPlans: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    var body: some View {
        let finished = summaries(model).filter { $0.total > 0 && $0.done == $0.total }
        let broken = model.mine.view.broken
        if !finished.isEmpty {
            SectionHeader("Done", count: finished.count)
            Card {
                Rows {
                    ForEach(finished) { x in
                        Button { model.push(.playbook(playbookId: x.track.playbookId, trackId: x.track.id)) } label: {
                            HStack(spacing: Space.sm) {
                                (Text("✓ ").foregroundColor(p.done) + Text(x.playbook?.title ?? "").foregroundColor(p.dim))
                                    .font(TypeStyle.label).frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(x.done)/\(x.total)").font(TypeStyle.caption).foregroundStyle(p.dim)
                                Text("›").font(TypeStyle.body).foregroundStyle(p.faint)
                            }
                            .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(x.playbook?.title ?? "Plan"), done")
                    }
                }
            }
        }
        if !broken.isEmpty {
            SectionHeader("Can't schedule", count: broken.count, tone: .late)
            Card {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(broken, id: \.trackId) { b in
                        Text(b.error).font(TypeStyle.caption).foregroundStyle(p.late)
                    }
                }
                .padding(Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Documents run out on their own schedule, so they surface here rather than in a tab.
private struct ExpiringDocs: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    var body: some View {
        let m = model.mine
        let now = model.now
        let expiring = groupDocuments(documentViews(m.documents, m.view, m.instances), now)[.expiring] ?? []
        if !expiring.isEmpty {
            SectionHeader("⚠ Expiring", count: expiring.count, tone: .late)
            Card {
                Rows {
                    ForEach(expiring) { d in
                        let on = d.expiresOn ?? now
                        let verb = on < now ? "expired" : "expires"
                        let needed = d.clash.map { " · needed by \($0.consumer.scheduled.title)" } ?? ""
                        Button { model.push(.document(documentId: d.id)) } label: {
                            HStack(spacing: Space.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).font(TypeStyle.label).foregroundStyle(p.text).lineLimit(1)
                                    Text("\(verb) \(formatDate(on)) · \(formatRelative(on, now: now).replacingOccurrences(of: "late", with: "ago"))\(needed)")
                                        .font(TypeStyle.caption).foregroundStyle(d.clash != nil ? p.late : p.dim)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text("›").font(TypeStyle.body).foregroundStyle(p.faint)
                            }
                            .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(d.name), \(verb) \(formatDate(on))\(needed.replacingOccurrences(of: " · ", with: ", "))")
                    }
                }
            }
        }
    }
}
