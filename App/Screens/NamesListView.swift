import SwiftUI
import PaperWorksCore

struct NamesListView: View {
    let cards: [BabyName]
    let header: String
    let surname: String
    let liked: [String]
    let onLike: (BabyName) -> Void
    let onSkip: (BabyName) -> Void
    let onOpen: (BabyName) -> Void
    @Environment(\.palette) private var p
    @State private var query = ""

    private var rows: [BabyName] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let hit = q.isEmpty ? cards : cards.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.meaning.localizedCaseInsensitiveContains(q)
                || ($0.hanzi?.contains(q) ?? false)
        }
        return hit.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func letter(_ n: BabyName) -> String {
        let c = n.name.folding(options: .diacriticInsensitive, locale: .current).prefix(1).uppercased()
        return c.first?.isLetter == true ? c : "#"
    }

    var body: some View {
        let sections = Dictionary(grouping: rows, by: letter).sorted { $0.key < $1.key }
        List {
            Text(header).font(TypeStyle.caption).foregroundStyle(p.dim).listRowBackground(Color.clear)
            ForEach(sections, id: \.key) { sec in
                Section(sec.key) {
                    ForEach(sec.value) { n in
                        row(n)
                            .listRowBackground(p.card)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or meaning")
        .animation(.default, value: rows.map(\.id))
        .overlay { if rows.isEmpty { Text("No names").font(TypeStyle.body).foregroundStyle(p.dim) } }
    }

    private func row(_ n: BabyName) -> some View {
        HStack(spacing: Space.md) {
            Button { withAnimation(.spring(duration: 0.35, bounce: 0.25)) { onOpen(n) } } label: {
                HStack(spacing: Space.md) {
                    Circle().fill(nameTint(n.gender)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        title(n)
                        Text(detail(n)).font(TypeStyle.caption).foregroundStyle(p.dim).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { onLike(n) } label: {
                Image(systemName: "heart").foregroundStyle(nameTint(.f)).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Like \(n.name)")
        }
    }

    private func title(_ n: BabyName) -> Text {
        var t: Text
        if let h = n.hanzi {
            t = Text(surname + h).font(.system(.body, design: .rounded).weight(.semibold)).foregroundColor(p.text)
            t = t + Text("  \(n.name)").font(TypeStyle.caption).foregroundColor(p.dim)
        } else {
            t = Text(n.name).font(.system(.body, design: .rounded).weight(.semibold)).foregroundColor(p.text)
            if !surname.isEmpty { t = t + Text(" \(surname)").font(.system(.body, design: .rounded)).foregroundColor(p.dim) }
        }
        let kin = (NAME_VARIANTS[nameGroup(n.id)] ?? []).filter { $0.id != n.id }
        if !kin.isEmpty {
            let more = kin.count > 3 ? "…" : ""
            t = t + Text("  · " + kin.prefix(3).map(\.name).joined(separator: ", ") + more)
                .font(TypeStyle.caption).foregroundColor(p.dim.opacity(0.7))
        }
        return t
    }

    private func detail(_ n: BabyName) -> String {
        var parts = ["\u{201C}\(n.meaning)\u{201D}"]
        if n.set == .zh, let s = n.source, !s.isEmpty { parts.append(sourceShort(s)) }
        if n.set == .en {
            if let o = n.origin, !o.isEmpty { parts.append(o) }
            if let r = rankLabel(n) { parts.append(r) }
        }
        return parts.joined(separator: " · ")
    }
}
