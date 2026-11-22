import SwiftUI
import PaperWorksCore

private let COMING_SOON = ["United States · life stages"]
/// Places they don't live in show this many, then "Show all".
private let FOLDED_SHOWN = 3

private struct Group: Identifiable {
    var key: String
    var title: String
    var items: [Playbook]
    var open: Bool
    var id: String { key }
}

struct LibraryScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var q = ""
    @State private var toggled: Set<String> = []
    @State private var importError: String?
    @State private var replacing: Playbook?
    @State private var choosing: PlanKind?

    var body: some View {
        let plan = model.mine
        let now = model.now
        let lives = plan.where
        let needle = q.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = model.playbooks
            .filter {
                needle.isEmpty || $0.title.lowercased().contains(needle)
                    || ($0.summary ?? "").lowercased().contains(needle) || ($0.region ?? "").lowercased().contains(needle)
            }
            .sorted { ($0.ages?.from ?? 99) < ($1.ages?.from ?? 99) }
        let tools = TOOL_PLAN_KINDS.filter {
            needle.isEmpty || $0.title.lowercased().contains(needle) || $0.summary.lowercased().contains(needle)
        }
        let soon = COMING_SOON.filter { needle.isEmpty || $0.lowercased().contains(needle) }
        let age = ageOn(plan.anchors, now)
        let notOutgrown = { (pb: Playbook) in
            pb.anchorKind != "born" || pb.ages?.to == nil || age == nil || age! <= pb.ages!.to!
        }
        let suggested = matches.filter { pb in
            notOutgrown(pb) && plan.anchors.contains { $0.kind == pb.anchorKind && fits(pb, whereFor(pb, $0, lives, plan.anchors)) }
        }
        let groups = byPlace(matches, lives).map { g -> Group in
            var g = g
            g.open = !needle.isEmpty || (toggled.contains(g.key) ? !g.open : g.open)
            return g
        }
        let decided = decidedBy(nil, plan.anchors, now)
        let whose = plan.person.id == ME ? "your" : "\(plan.person.name)'s"
        let livesDetail = decided.map { "From \(whose) \"\(anchorDisplay($0))\" event · \($0.location ?? "")" }
            ?? "Add a move or an event with a place to open the plans that apply"

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Card {
                    ListRow(lives.country != nil ? "Lives in \(whereName(lives) ?? "")" : "Where do they live?",
                            detail: livesDetail,
                            onPress: {
                                if let decided { model.push(.anchorEdit(anchorId: decided.id, kind: nil)) }
                                else { model.push(.anchorEdit(anchorId: nil, kind: "moved-city")) }
                            },
                            tone: .accent)
                }
                .padding(.top, Space.sm)

                if !suggested.isEmpty {
                    SectionHeader(
                        "Fits your events", count: suggested.count,
                        info: "Plans that hang off a kind of event this person already has, fit where that event happened, and that they haven't aged past.")
                    Card { Rows { ForEach(suggested) { row($0, plan) } } }
                }
                ForEach(groups) { g in
                    SectionHeader(g.title, count: g.items.count)
                    Card {
                        Rows {
                            ForEach(g.open ? g.items : Array(g.items.prefix(FOLDED_SHOWN))) { row($0, plan) }
                            if g.items.count > FOLDED_SHOWN && needle.isEmpty {
                                ListRow(g.open ? "Show fewer" : "Show all \(g.items.count)",
                                        onPress: { toggle(g.key) }, chevron: false, tone: .accent)
                            }
                        }
                    }
                }
                if !tools.isEmpty {
                    SectionHeader("Other kinds of plans", count: tools.count)
                    Card { Rows { ForEach(tools, id: \.kind) { toolRow($0) } } }
                }
                if !soon.isEmpty {
                    SectionHeader("Coming soon", info: "Life-stage plans cover Canada and China for now; other countries have visa plans.")
                    Card {
                        Rows {
                            ForEach(soon, id: \.self) { r in
                                ListRow(r, tone: .dim, accessibilityLabel: "\(r), coming soon")
                            }
                        }
                    }
                }
                PWButton(title: "Import a playbook file…") { Task { await importPlaybook() } }
                    .padding(Space.lg).padding(.top, Space.sm)
            }
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(p.bg.ignoresSafeArea())
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .sheet(item: $choosing) { kind in
            EventPicker(current: nil, marksCurrent: false) { id in
                if let new = model.addToolPlan(kind, anchorId: id) { model.push(.names(planId: new)) }
            } onNew: { model.push(.anchorEdit(anchorId: nil, kind: "baby-due")) }
                .presentationDetents([.medium, .large])
        }
        .alert("Can't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .alert("Replace \"\(replacing?.title ?? "")\"?", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                if let pb = replacing {
                    model.savePlaybook(pb)
                    model.push(.playbook(playbookId: pb.id, trackId: nil))
                }
            }
        } message: {
            Text("A playbook with the same id is already in your library. Plans using it reflow against the new steps.")
        }
    }

    private func toggle(_ key: String) {
        if toggled.contains(key) { toggled.remove(key) } else { toggled.insert(key) }
    }

    private func row(_ pb: Playbook, _ plan: Mine) -> some View {
        let attached = plan.tracks.contains { $0.playbookId == pb.id }
        return ListRow(
            pb.title,
            value: attached ? "✓ attached" : "\(pb.steps.count) steps",
            detail: "from \"\(kindLabel(pb.anchorKind))\"\(pb.ages.map { " · \(formatAges($0))" } ?? "")",
            onPress: {
                model.push(.playbook(playbookId: pb.id, trackId: plan.tracks.first { $0.playbookId == pb.id }?.id))
            })
    }

    private func toolRow(_ t: ToolPlanKind) -> some View {
        let have = model.toolPlans(t.kind)
        return HStack(spacing: Space.md) {
            Image(systemName: t.symbol).font(.title2).foregroundStyle(p.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(TypeStyle.label).foregroundStyle(p.text)
                Text(t.summary).font(TypeStyle.caption).foregroundStyle(p.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !have.isEmpty { Text(have.count == 1 ? "Added ✓" : "\(have.count) added ✓").font(TypeStyle.label).foregroundStyle(p.accent) }
            Button("Add") { choosing = t.kind }.buttonStyle(.pwPlain)
        }
        .padding(.horizontal, Space.lg).padding(.vertical, Space.md)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture { if have.count == 1 { model.push(.names(planId: have[0].id)) } }
    }

    private func importPlaybook() async {
        guard let path = await Files.shared.pickFile(["public.json", "public.plain-text"]) else { return }
        guard let text = try? Files.readText(path),
              let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8))
        else { importError = "This file isn't JSON."; return }
        switch validatePlaybook(parsed) {
        case .failure(let message): importError = message
        case .ok(let playbook):
            if model.playbooks.contains(where: { $0.id == playbook.id }) {
                replacing = playbook
            } else {
                model.savePlaybook(playbook)
                model.push(.playbook(playbookId: playbook.id, trackId: nil))
            }
        }
    }

    /// Country, then within Canada nationwide and each province. Where they live comes first and open.
    private func byPlace(_ playbooks: [Playbook], _ lives: Where) -> [Group] {
        let countries = COUNTRIES.sorted { a, b in a.code == lives.country && b.code != lives.country }
        var groups: [Group] = []
        for c in countries {
            let mine = playbooks.filter { $0.country == c.code }
            var seen = Set<String>()
            let provinces = mine.compactMap(\.province).filter { seen.insert($0).inserted }.sorted { a, b in
                if a == lives.province { return b != lives.province }
                if b == lives.province { return false }
                return (provinceName(a) ?? a) < (provinceName(b) ?? b)
            }
            let nationwide = mine.filter { $0.province == nil }
            func fitsHere(_ province: String?) -> Bool {
                c.code == lives.country && (province == nil || lives.province == nil || province == lives.province)
            }
            if !nationwide.isEmpty {
                groups.append(Group(key: c.code, title: provinces.isEmpty ? c.name : "\(c.name) · nationwide",
                                    items: nationwide, open: fitsHere(nil)))
            }
            for pr in provinces {
                groups.append(Group(key: "\(c.code)-\(pr)", title: "\(c.name) · \(provinceName(pr) ?? pr)",
                                    items: mine.filter { $0.province == pr }, open: fitsHere(pr)))
            }
        }
        let other = playbooks.filter { pb in !COUNTRIES.contains { $0.code == pb.country } }
        if !other.isEmpty { groups.append(Group(key: "other", title: "Other", items: other, open: false)) }
        return groups.filter { !$0.items.isEmpty }
    }
}
