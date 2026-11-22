import SwiftUI
import PaperWorksCore

/// Next steps shows the nearest few; the full list is below.
private typealias Anchor = PaperWorksCore.Anchor
private let NEXT_SHOWN = 3
private let SOURCES_SHOWN = 3

struct PlaybookScreen: View {
    let playbookId: String
    let trackId: String?
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @Environment(\.openURL) private var openURL
    @State private var previewPick: String?
    @State private var aboutOpen = false
    @State private var allSources = false
    @State private var pickingAnchor = false
    @State private var detaching = false
    @State private var snoozing: String?

    private var playbook: Playbook? { model.playbooks.first { $0.id == playbookId } }
    private var track: Track? { model.mine.tracks.first { $0.id == trackId } }
    /// Events of the kind this plan is written for.
    private var suggested: [Anchor] { model.mine.anchors.filter { $0.kind == playbook?.anchorKind } }
    /// Any event on the board can anchor any plan; the plan's own kind comes first.
    private var candidates: [Anchor] {
        suggested + model.mine.anchors.filter { $0.kind != playbook?.anchorKind }.sorted { $0.date > $1.date }
    }

    private var previewId: String? {
        if let previewPick { return previewPick }
        let plan = model.mine
        if let playbook,
           let hit = suggested.first(where: { fits(playbook, whereFor(playbook, $0, plan.where, plan.anchors)) }) { return hit.id }
        return suggested.first?.id
    }

    var body: some View {
        Group {
            if let playbook { content(playbook) } else { Color.clear }
        }
        .background(p.bg.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if let playbook { ToolbarItem(placement: .topBarTrailing) { menu(playbook) } } }
        .snoozeDialog($snoozing)
        .confirmationDialog("Anchor on", isPresented: $pickingAnchor, titleVisibility: .visible) {
            ForEach(candidates) { a in
                Button("\(anchorDisplay(a)) · \(formatPrecise(a.date, a.precision))") {
                    if let track { model.reanchorTrack(track.id, a.id) } else { previewPick = a.id }
                }
            }
            Button("Add a new event…") { model.push(.anchorEdit(anchorId: nil, kind: nil)) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Detach \"\(playbook?.title ?? "")\"?", isPresented: $detaching) {
            Button("Cancel", role: .cancel) {}
            Button("Detach", role: .destructive) {
                if let track { model.detachTrack(track.id) }
                model.pop()
            }
        } message: {
            let steps = trackSteps
            let done = steps.filter { $0.status == .done }.count
            Text("\(steps.count) steps go\(done > 0 ? ", including \(done) done" : "").")
        }
    }

    private var trackSteps: [PlannedStep] {
        guard let track else { return [] }
        return model.mine.view.steps.filter { $0.trackId == track.id }
    }

    private func haptic(_ kind: HapticKind) { if model.settings.haptics { Haptics.play(kind) } }

    // MARK: actions

    private func menu(_ playbook: Playbook) -> some View {
        Menu {
            Button("Duplicate") {
                if let id = model.duplicatePlaybook(playbook.id) { model.push(.playbook(playbookId: id, trackId: nil)) }
            }
            Button("Export…") { export(playbook) }
            if track != nil { Button("Detach", role: .destructive) { detaching = true } }
        } label: {
            Text("⋯").font(TypeStyle.headline).foregroundStyle(p.accent)
        }
        .accessibilityLabel("More")
    }

    private func export(_ playbook: Playbook) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(playbook), let json = String(data: data, encoding: .utf8) else { return }
        Task {
            guard let path = try? Files.writeTemp("\(playbook.id).json", text: json) else { return }
            _ = await Files.share(path)
        }
    }

    private func attach(_ playbook: Playbook, _ anchor: Anchor?) {
        guard let anchor else { return }
        model.attachTrack(playbook.id, anchor.id)
        haptic(.success)
        model.popToRoot()
    }

    private func swipeActions(_ s: PlannedStep) -> (leading: [SwipeAction], trailing: [SwipeAction]) {
        let id = s.instanceId
        return (
            [SwipeAction(label: "Not for me", color: p.dim) { model.skip(id) }],
            [SwipeAction(label: "Done", color: p.done) { haptic(.success); model.markDone(id) },
             SwipeAction(label: "Snooze", color: p.accent) { snoozing = id }])
    }

    // MARK: body

    private func content(_ playbook: Playbook) -> some View {
        let plan = model.mine
        let now = model.now
        let anchor = plan.anchors.first { $0.id == (track?.anchorId ?? previewId) }
        let due = whereFor(playbook, anchor, plan.where, plan.anchors)
        let twin = twinFor(playbook, due, model.playbooks)
        let buckets = bucketize(trackSteps, now)
        let actNow = buckets[.now] ?? []
        let nextSteps = Array(((buckets[.d90] ?? []) + (buckets[.year] ?? []) + (buckets[.later] ?? [])).prefix(NEXT_SHOWN))
        let decided = decidedBy(anchor, plan.anchors, now)
        let whose = plan.person.id == ME ? "your" : "\(plan.person.name)'s"
        let sources = playbook.sources ?? []
        let ordered = (try? topoSort(playbook.steps)) ?? playbook.steps
        let depth = depths(ordered)

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                head(playbook, now)

                if !fits(playbook, due) {
                    Card {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("This plan follows \(rulesName(playbook) ?? "other") rules, but \(wrongWhere(decided, whose, due)).")
                                .font(TypeStyle.body).foregroundStyle(p.text)
                            HStack(spacing: Space.lg) {
                                if let decided {
                                    Button("Edit event") { model.push(.anchorEdit(anchorId: decided.id, kind: nil)) }
                                        .buttonStyle(.pwPlain)
                                }
                                if let twin {
                                    Button(track != nil ? "Switch to \(whereName(due) ?? "")" : "See \(whereName(due) ?? "")") {
                                        var next: String?
                                        if let track { next = model.switchTrack(track.id, twin.id) }
                                        model.pop()
                                        model.push(.playbook(playbookId: twin.id, trackId: next))
                                    }
                                    .buttonStyle(.pwPlain)
                                }
                            }
                        }
                        .padding(Space.md).frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.accentSoft)
                    }
                    .padding(.top, Space.sm)
                }

                if track == nil {
                    VStack(alignment: .leading, spacing: Space.md) {
                        PWButton(title: "Attach to my plan", kind: .primary) { attach(playbook, anchor) }
                            .disabled(anchor == nil)
                        if anchor == nil {
                            HStack(spacing: Space.sm) {
                                Text("Link it to an event: \"\(kindLabel(playbook.anchorKind))\" fits best, but any event works.")
                                    .font(TypeStyle.body).foregroundStyle(p.text).frame(maxWidth: .infinity, alignment: .leading)
                                if !candidates.isEmpty {
                                    Button("Choose") { pickingAnchor = true }.buttonStyle(.pwPlain)
                                }
                                Button("Add") { model.push(.anchorEdit(anchorId: nil, kind: playbook.anchorKind)) }
                                    .buttonStyle(.pwPlain)
                            }
                            .padding(Space.md).background(p.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                        }
                    }
                    .padding(Space.lg)
                }

                if let anchor { anchorCard(playbook, anchor) }

                if !actNow.isEmpty {
                    SectionHeader("Act now", count: actNow.count)
                    Card { Rows(inset: Space.lg + 18 + Space.sm) { ForEach(actNow, id: \.instanceId) { swipeRow($0) } } }
                }
                if !nextSteps.isEmpty {
                    SectionHeader("Next steps")
                    Card { Rows(inset: Space.lg + 18 + Space.sm) { ForEach(nextSteps, id: \.instanceId) { swipeRow($0) } } }
                }
                if !actNow.isEmpty || !nextSteps.isEmpty {
                    Text("Press and hold a step for Done, Snooze or Not for me.")
                        .font(TypeStyle.caption).foregroundStyle(p.faint)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                        .padding(.horizontal, Space.lg).padding(.top, Space.sm)
                }

                SectionHeader(track != nil ? "All steps" : "Steps", count: playbook.steps.count)
                Card {
                    Rows {
                        if track != nil {
                            ForEach(trackSteps, id: \.instanceId) { s in
                                StepRow(step: s.scheduled, now: now, move: model.moves[s.instanceId]) {
                                    model.push(.step(instanceId: s.instanceId))
                                }
                            }
                        } else {
                            ForEach(Array(ordered.enumerated()), id: \.element.id) { i, s in
                                TemplateRow(step: s, n: i + 1, depth: depth[s.id] ?? 0)
                            }
                        }
                    }
                }

                if !sources.isEmpty {
                    SectionHeader(
                        "Sources",
                        info: "Where the playbook's author checked the steps. Opens in Safari — the app itself sends nothing.")
                    Card {
                        Rows {
                            ForEach(Array((allSources ? sources : Array(sources.prefix(SOURCES_SHOWN))).enumerated()), id: \.offset) { _, s in
                                ListRow(s.title,
                                        detail: s.url.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
                                            .split(separator: "/").first.map(String.init),
                                        onPress: { if let url = URL(string: s.url) { openURL(url) } },
                                        tone: .accent)
                            }
                        }
                    }
                    if sources.count > SOURCES_SHOWN {
                        Button(allSources ? "Show fewer" : "Show all \(sources.count)") { allSources.toggle() }
                            .buttonStyle(.pwPlain)
                            .padding(.leading, Space.lg).padding(.top, Space.sm)
                    }
                }
            }
            .padding(.bottom, 120)
        }
    }

    private func wrongWhere(_ decided: Anchor?, _ whose: String, _ due: Where) -> String {
        if let decided, let location = decided.location {
            return "\(whose) \"\(anchorDisplay(decided))\" event is in \(location)."
        }
        return "this counts as \(whereName(due) ?? "somewhere else")."
    }

    private func head(_ playbook: Playbook, _ now: CivilDate) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(playbook.title).font(TypeStyle.title).foregroundStyle(p.text).accessibilityAddTraits(.isHeader)
            Text("\(playbook.steps.count) steps · anchored on \"\(kindLabel(playbook.anchorKind))\"\(playbook.region.map { " · \($0)" } ?? "")")
                .font(TypeStyle.caption).foregroundStyle(p.dim)
            if playbook.summary != nil || playbook.ages != nil || !(playbook.conditions ?? []).isEmpty {
                Button { aboutOpen.toggle() } label: {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        if let summary = playbook.summary {
                            Text(summary).font(TypeStyle.body).foregroundStyle(p.text)
                                .lineLimit(aboutOpen ? nil : 2).multilineTextAlignment(.leading)
                        }
                        if aboutOpen { AppliesIf(ages: playbook.ages, conditions: playbook.conditions) }
                        Text(aboutOpen ? "Less" : "More").font(TypeStyle.caption).foregroundStyle(p.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint(aboutOpen ? "Folds the description" : "Shows the whole description")
            }
            Disclaimer(playbook: playbook, now: now)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.lg).padding(.top, Space.sm)
    }

    private func anchorCard(_ playbook: Playbook, _ anchor: Anchor) -> some View {
        let preview = previewRange(playbook, anchor)
        return Card {
            Rows {
                ListRow("Anchored on", value: formatPrecise(anchor.date, anchor.precision), detail: anchorDisplay(anchor),
                        onPress: { pickingAnchor = true })
                if let preview {
                    ListRow("First step", value: "\(track != nil ? "starts" : "would start") \(formatMonth(preview.first))", chevron: false)
                    ListRow("Last step", value: "\(track != nil ? "finishes" : "would finish") \(formatMonth(preview.last))", chevron: false)
                }
            }
        }
        .padding(.top, Space.md)
    }

    private func previewRange(_ playbook: Playbook, _ anchor: Anchor) -> (first: CivilDate, last: CivilDate)? {
        let t = Track(id: "preview", playbookId: playbook.id, anchorEventDate: resolve(anchor.date, anchor.precision))
        guard let scheduled = try? schedule(playbook, t, []),
              let first = scheduled.map(\.startBy).min(), let last = scheduled.map(\.dueBy).max() else { return nil }
        return (first, last)
    }

    @ViewBuilder private func swipeRow(_ s: PlannedStep) -> some View {
        let actions = swipeActions(s)
        StepRow(step: s.scheduled, now: model.now, move: model.moves[s.instanceId]) {
            model.push(.step(instanceId: s.instanceId))
        }
        .contextMenu {
            ForEach(actions.trailing + actions.leading) { a in Button(a.label, action: a.perform) }
        }
        .accessibilityAction(named: "Done") { actions.trailing[0].perform() }
        .accessibilityAction(named: "Snooze") { actions.trailing[1].perform() }
        .accessibilityAction(named: "Not for me") { actions.leading[0].perform() }
    }

    /// Longest chain of prerequisites before each step: the tree's indent.
    private func depths(_ ordered: [StepTemplate]) -> [String: Int] {
        var out: [String: Int] = [:]
        for s in ordered {
            out[s.id] = s.dependsOn.isEmpty ? 0 : min(4, 1 + (s.dependsOn.map { out[$0] ?? 0 }.max() ?? 0))
        }
        return out
    }
}

private struct TemplateRow: View {
    let step: StepTemplate
    let n: Int
    let depth: Int
    @Environment(\.palette) private var p

    var body: some View {
        var bits = ["takes \(formatDuration(step.durationDays))"]
        if let v = step.validForDays { bits.append("valid \(formatDuration(v))") }
        return HStack(alignment: .top, spacing: Space.sm) {
            Text(depth > 0 ? "└" : String(n)).font(TypeStyle.caption).foregroundStyle(p.dim)
                .frame(width: 18, alignment: .leading).padding(.top, 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(step.title).font(TypeStyle.body).foregroundStyle(p.text)
                Text(bits.joined(separator: " · ")).font(TypeStyle.caption).foregroundStyle(p.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Space.lg + CGFloat(depth) * 12).padding(.trailing, Space.lg).padding(.vertical, Space.md)
    }
}
