import SwiftUI
import PaperWorksCore

private typealias Anchor = PaperWorksCore.Anchor

private let behind = ["graduated", "first-job", "migrated", "married", "child-born", "home-bought"]

struct FirstRunScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    @State private var step = 1
    @State private var kind: String?
    @State private var when = ""
    @State private var picked: String?
    @State private var trackDate = ""

    private var thisYear: Int { Int(model.now.prefix(4)) ?? 2026 }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.md) {
                Text("\(step) of 2").font(TypeStyle.caption).foregroundStyle(p.dim)
                if step == 1 { one } else { two }
            }
            .padding(.horizontal, Space.lg).padding(.vertical, Space.xxl)
        }
        .background(p.bg)
        .onAppear {
            if when.isEmpty { when = "\(thisYear - 2)-01-15" }
            if trackDate.isEmpty { trackDate = model.now }
        }
    }

    private func centered(_ text: String, _ font: Font, _ color: Color) -> some View {
        Text(text).font(font).foregroundStyle(color).multilineTextAlignment(.center)
    }

    private var one: some View {
        Group {
            centered("Paper Works", TypeStyle.title, p.text)
            centered("Paperwork for life's big moves, laid out in order.", TypeStyle.body, p.dim)
            centered("Anything recent that still has forms to file?", TypeStyle.headline, p.text).padding(.top, Space.lg)
            Card {
                Rows {
                    ForEach(behind, id: \.self) { k in
                        Button { kind = kind == k ? nil : k } label: {
                            HStack(spacing: Space.sm) {
                                Text(kind == k ? "✓" : "").foregroundStyle(p.accent).frame(width: 18)
                                Text(kindLabel(k)).font(TypeStyle.body).foregroundStyle(p.text)
                                Spacer(minLength: 0)
                            }
                            .padding(Space.lg).frame(minHeight: 48).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(kindLabel(k))
                        .accessibilityAddTraits(kind == k ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, -Space.lg)
            if kind != nil {
                Text("When, roughly?").font(TypeStyle.label).foregroundStyle(p.text).padding(.top, Space.lg)
                Card { DateWheel(date: $when, precision: .month, years: (thisYear - 60)...thisYear) }
                    .padding(.horizontal, -Space.lg)
            }
            HStack(spacing: Space.md) {
                PWButton(title: "Skip") { step = 2 }.frame(maxWidth: .infinity)
                PWButton(title: "Add", kind: .primary) {
                    if let kind {
                        model.saveAnchor(Anchor(id: "", kind: kind, label: kindLabel(kind), date: when, precision: .month))
                        Haptics.play(.light)
                    }
                    step = 2
                }
                .disabled(kind == nil || resolve(when, .month) > model.now)
                .frame(maxWidth: .infinity)
            }
            .padding(.top, Space.md)
        }
    }

    private var two: some View {
        Group {
            centered("Pick a plan", TypeStyle.title, p.text)
            centered("A plan turns an event into dated paperwork steps. It's guidance, not advice.", TypeStyle.body, p.dim)
            Card {
                Rows {
                    ForEach(model.playbooks, id: \.id) { pb in
                        let has = model.mine.anchors.contains { $0.kind == pb.anchorKind }
                        let open = picked == pb.id
                        VStack(spacing: 0) {
                            Button { has ? attach(pb) : (picked = open ? nil : pb.id) } label: {
                                HStack(spacing: Space.sm) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pb.title).font(TypeStyle.label).foregroundStyle(p.text)
                                        if let s = pb.summary { Text(s).font(TypeStyle.caption).foregroundStyle(p.dim) }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(open ? "⌄" : "›").foregroundStyle(p.faint)
                                }
                                .padding(Space.lg).frame(minHeight: 48).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(spoken("\(pb.title). \(pb.summary ?? "")"))
                            if open {
                                VStack(alignment: .leading, spacing: Space.sm) {
                                    Text("\(kindById(pb.anchorKind)?.label ?? pb.anchorKind) — when?")
                                        .font(TypeStyle.caption).foregroundStyle(p.dim).padding(.horizontal, Space.lg)
                                    DateWheel(date: $trackDate, years: (thisYear - 10)...(thisYear + 15))
                                    PWButton(title: "Attach", kind: .primary) { attach(pb) }.padding(.horizontal, Space.lg)
                                }
                                .padding(.bottom, Space.md)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, -Space.lg)
            PWButton(title: "Later", kind: .plain, action: finish).padding(.top, Space.md)
        }
    }

    private func finish() { model.updateSettings { $0.firstRunDone = true } }

    private func attach(_ pb: Playbook) {
        if let existing = model.mine.anchors.first(where: { $0.kind == pb.anchorKind }) {
            model.attachTrack(pb.id, existing.id)
        } else {
            model.saveAnchor(Anchor(id: "", kind: pb.anchorKind, label: kindLabel(pb.anchorKind), date: trackDate, precision: .day),
                             attach: [pb.id])
        }
        Haptics.play(.success)
        finish()
    }
}
