import SwiftUI
import PaperWorksCore

struct SourcesScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    var body: some View {
        let bundled = Set(bundledPlaybooks.map(\.id))
        let byAge = model.playbooks.sorted { $0.reviewedAt < $1.reviewedAt }
        let groups = [
            (title: "Bundled with the app", items: byAge.filter { bundled.contains($0.id) }),
            (title: "Yours", items: byAge.filter { !bundled.contains($0.id) }),
        ]
        ScrollView {
            VStack(spacing: 0) {
                Text("Oldest review first. A playbook over two years old is labelled, never hidden — check its steps against the current rules.")
                    .font(TypeStyle.caption).foregroundStyle(p.dim)
                    .padding(.horizontal, Space.lg).padding(.top, Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(groups.filter { !$0.items.isEmpty }, id: \.title) { g in
                    SectionHeader(g.title, count: g.items.count)
                    Card {
                        Rows {
                            ForEach(g.items, id: \.id) { pb in
                                let stale = isStale(pb, model.now)
                                ListRow(pb.title, value: (stale ? "⚠ " : "") + formatMonth(pb.reviewedAt),
                                        onPress: { model.push(.playbook(playbookId: pb.id, trackId: nil)) },
                                        tone: stale ? .late : .normal)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 80)
        }
        .background(p.bg)
        .navigationTitle("Playbooks")
        .navigationBarTitleDisplayMode(.inline)
    }
}
