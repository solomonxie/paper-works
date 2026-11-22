import SwiftUI
import PaperWorksCore

struct ChapterScreen: View {
    let eventId: String
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var notice: Notice?

    private struct Notice: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    var body: some View {
        let m = model.mine
        let now = model.now
        let nodes = timelineNodes(m.anchors, m.tracks, m.view.steps, now)
        if let node = nodes.first(where: { $0.id == eventId }) {
            content(node: node, nodes: nodes, m: m, now: now)
        }
    }

    @ViewBuilder
    private func content(node: TimelineNode, nodes: [TimelineNode], m: Mine, now: CivilDate) -> some View {
        let chapter = eventChapters(nodes, now).first { $0.eventId == eventId }
        let anchor = m.anchors.first { $0.id == eventId }
        let other = model.plan.people.first { $0.id == anchor?.withPersonId }
        let purpose = kindById(anchor?.kind ?? "")?.purposes?.first { $0.id == anchor?.purpose }?.label
        let next = nodes.first { $0.date > node.date && $0.moment != true }
        let trackIds = Set(m.tracks.filter { $0.anchorId == eventId }.map(\.id))
        let steps = openSteps(m.view.steps.filter { s in
            trackIds.contains(s.trackId) || (chapter.map { !chapterSteps($0, [s]).isEmpty } ?? false)
        }).sorted { $0.startBy < $1.startBy }
        let past = chapter?.end.map { $0 <= now } ?? false
        let unlocks: [Playbook] = anchor.map { a in
            plansFor(a, m.where, model.playbooks, m.anchors).filter { pb in
                countsFrom(pb, a, model.plan.anchors).map { ownerOf($0) == m.person.id } ?? false
            }
        } ?? []
        let years = chapter?.end.map { max(1, Int((Double(diffDays(chapter!.start, $0)) / 365.25).rounded())) }
        let yearN = chapter.map { Int((Double(diffDays($0.start, now)) / 365.25).rounded(.down)) + 1 }
        let title = chapter?.label ?? node.label
        let tools = anchor.map { toolPlanKinds(suggestedBy: $0.kind) } ?? []

        ScrollView {
            VStack(spacing: 0) {
                head(node, chapter, anchor, purpose, years, yearN, now)
                if let other {
                    Card {
                        ListRow("\(other.name)'s life", detail: "Their board: their events and plans", onPress: {
                            model.switchPerson(other.id)
                            model.popToRoot()
                        }, tone: .accent)
                    }
                    .padding(.top, Space.sm)
                }
                if !unlocks.isEmpty || !tools.isEmpty { opens(unlocks, tools, anchor) }
                if !steps.isEmpty || !past {
                    SectionHeader(chapter?.isCurrent == true ? "Active steps" : "Steps", count: steps.count)
                }
                if !steps.isEmpty {
                    Card {
                        Rows(inset: Space.lg + 18 + Space.sm) {
                            ForEach(Array(steps.prefix(30)), id: \.scheduled.instanceId) { s in
                                StepRow(step: s.scheduled, now: now, subtitle: s.playbook.title,
                                        move: model.moves[s.scheduled.instanceId]) {
                                    model.push(.step(instanceId: s.scheduled.instanceId))
                                }
                            }
                        }
                    }
                } else if !past {
                    Text("Nothing to start in this stretch.").font(TypeStyle.body).foregroundStyle(p.dim)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Space.lg)
                }
                if let anchor { notes(anchor) }
                if let next {
                    SectionHeader("Ends with")
                    Card {
                        ListRow("○ \(next.label)", value: formatPrecise(next.date, next.precision)) {
                            model.push(.chapter(eventId: next.id))
                        }
                    }
                }
                if let anchor {
                    VStack(spacing: Space.md) {
                        if !steps.isEmpty {
                            Button("Export to Reminders") { Task { await export(title, steps) } }.buttonStyle(.pwPlain)
                        }
                        Button("Edit this event") { model.push(.anchorEdit(anchorId: anchor.id, kind: nil)) }
                            .buttonStyle(.pwSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Space.lg).padding(.top, Space.xl)
                }
            }
            .padding(.bottom, 120)
        }
        .background(p.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $notice) { n in Alert(title: Text(n.title), message: Text(n.message), dismissButton: .default(Text("OK"))) }
    }

    private func head(_ node: TimelineNode, _ chapter: Chapter?, _ anchor: PaperWorksCore.Anchor?, _ purpose: String?,
                      _ years: Int?, _ yearN: Int?, _ now: CivilDate) -> some View {
        var line: String
        if let end = node.end {
            line = "\(formatPrecise(node.date, node.precision)) – \(formatPrecise(end, node.precision)) · \(formatLasts(node.date, end))"
        } else if chapter?.isCurrent == true, let years, let yearN {
            line = "year \(yearN) of \(years)"
        } else if node.date > now {
            line = "starts \(formatPrecise(node.date, node.precision))"
        } else {
            line = "since \(formatPrecise(node.date, node.precision))"
        }
        if let loc = anchor?.location, !loc.isEmpty { line += " · \(loc)" }
        if let purpose { line += " · \(purpose)" }
        return Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                if let chapter { ChapterBar(start: chapter.start, end: chapter.end, now: now) }
                Text(line).font(TypeStyle.caption).foregroundStyle(p.dim)
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, Space.sm)
    }

    private func opens(_ unlocks: [Playbook], _ tools: [ToolPlanKind], _ anchor: PaperWorksCore.Anchor?) -> some View {
        VStack(spacing: 0) {
            SectionHeader("Opens")
            Card {
                Rows {
                    ForEach(unlocks) { pb in
                        let on = anchor.flatMap { countsFrom(pb, $0, model.plan.anchors) }
                        let track = model.plan.tracks.first { $0.playbookId == pb.id && $0.anchorId == on?.id }
                        ListRow(pb.title, value: track != nil ? "✓ attached" : "\(pb.steps.count) steps") {
                            model.push(.playbook(playbookId: pb.id, trackId: track?.id))
                        }
                    }
                    ForEach(tools, id: \.kind) { t in
                        let have = model.toolPlan(t.kind, anchorId: anchor?.id)
                        ListRow(t.title, value: have != nil ? "✓ added" : nil, detail: have != nil ? nil : t.summary) {
                            if let id = have?.id ?? anchor.flatMap({ model.addToolPlan(t.kind, anchorId: $0.id) }) {
                                model.push(.names(planId: id))
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func notes(_ anchor: PaperWorksCore.Anchor) -> some View {
        SectionHeader("Notes")
        if let note = anchor.note, !note.isEmpty {
            Card {
                Button { model.push(.anchorEdit(anchorId: anchor.id, kind: nil)) } label: {
                    Text(note).font(TypeStyle.body).foregroundStyle(p.text)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.lg).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edits the notes")
            }
        } else {
            Button("+ Add notes") { model.push(.anchorEdit(anchorId: anchor.id, kind: nil)) }
                .buttonStyle(.pwPlain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.lg).padding(.top, Space.sm)
        }
    }

    private func export(_ listTitle: String, _ steps: [PlannedStep]) async {
        let items = steps.map {
            DatedEntry(title: $0.scheduled.title, date: $0.startBy,
                       notes: "Start by \(formatShort($0.startBy)), due \(formatShort($0.dueBy)) · \($0.playbook.title). From Paper Works — a plan, not advice.")
        }
        let n = try? await ReminderExport.export(listTitle, items: items)
        if let n {
            if n < 0 {
                notice = Notice(title: "Reminders access is off", message: "Turn it on in Settings → Paper Works → Reminders.")
            } else {
                Haptics.play(.success)
                notice = Notice(title: n > 0 ? "Added \(n) step\(n == 1 ? "" : "s") to Reminders" : "Already in Reminders",
                                message: "In the list “\(listTitle)”, due on each start-by date.")
            }
        } else {
            notice = Notice(title: "Couldn't export", message: "Reminders didn’t take the list. Try again.")
        }
    }
}
