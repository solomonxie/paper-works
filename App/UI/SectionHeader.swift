import SwiftUI

/// HEADING ⓘ                (n) — optionally collapsible, remembered by the caller.
struct SectionHeader<Right: View>: View {
    enum Tone { case normal, late }

    let title: String
    var count: String?
    var info: String?
    var tone: Tone = .normal
    var collapsed: Bool?
    var onToggle: (() -> Void)?
    @ViewBuilder var right: Right
    @Environment(\.palette) private var p

    init(_ title: String, count: Int? = nil, info: String? = nil, tone: Tone = .normal,
         collapsed: Bool? = nil, onToggle: (() -> Void)? = nil, @ViewBuilder right: () -> Right) {
        self.title = title; self.count = count.map(String.init); self.info = info; self.tone = tone
        self.collapsed = collapsed; self.onToggle = onToggle; self.right = right()
    }

    var body: some View {
        if let onToggle {
            HStack(spacing: Space.sm) {
                Button(action: onToggle) { header(chevron: true) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(spoken("\(title), \(count ?? "")"))
                    .accessibilityValue(collapsed == true ? "collapsed" : "expanded")
                if let info { InfoPopover(text: info) }
            }
            .padding(.horizontal, Space.lg).padding(.top, Space.xl).padding(.bottom, Space.sm).frame(minHeight: 44)
        } else {
            HStack(spacing: Space.sm) {
                header(chevron: false)
                if let info { InfoPopover(text: info) }
            }
            .padding(.horizontal, Space.lg).padding(.top, Space.xl).padding(.bottom, Space.sm).frame(minHeight: 44)
        }
    }

    private func header(chevron: Bool) -> some View {
        HStack(spacing: Space.sm) {
            Text(title.uppercased())
                .font(TypeStyle.heading).tracking(TypeStyle.headingTracking)
                .foregroundStyle(tone == .late ? p.late : p.dim)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            right
            if let count { Text("(\(count))").font(TypeStyle.caption).foregroundStyle(p.dim) }
            if chevron {
                Text(collapsed == true ? "›" : "⌄").font(TypeStyle.caption).foregroundStyle(p.dim)
            }
        }
        .contentShape(Rectangle())
    }
}

extension SectionHeader where Right == EmptyView {
    init(_ title: String, count: Int? = nil, info: String? = nil, tone: Tone = .normal,
         collapsed: Bool? = nil, onToggle: (() -> Void)? = nil) {
        self.init(title, count: count, info: info, tone: tone, collapsed: collapsed, onToggle: onToggle) { EmptyView() }
    }
}
