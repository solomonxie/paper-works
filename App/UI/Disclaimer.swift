import SwiftUI
import PaperWorksCore

/// On every playbook and step surface. Never dismissible, never a modal.
struct Disclaimer: View {
    let playbook: Playbook
    let now: CivilDate
    var onPress: (() -> Void)?
    @Environment(\.palette) private var p

    var body: some View {
        let stale = isStale(playbook, now)
        let years = reviewAgeYears(playbook.reviewedAt, now)
        let reviewed = "Reviewed \(formatMonth(playbook.reviewedAt)) · not official advice"
        let warning = "⚠ Over \(years) years old. Check the steps against the current rules."
        let content = VStack(alignment: .leading, spacing: 2) {
            Text(reviewed).font(TypeStyle.caption).foregroundStyle(p.dim)
            if stale {
                HStack(spacing: Space.sm) {
                    Text(warning).font(TypeStyle.caption).foregroundStyle(p.warn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if onPress != nil { Text("›").foregroundStyle(p.faint) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if let onPress {
            Button(action: onPress) { content }.buttonStyle(.plain).accessibilityLabel(spoken(stale ? "\(reviewed). \(warning)" : reviewed))
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}
