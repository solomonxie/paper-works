import SwiftUI
import PaperWorksCore

/// Who a playbook or step is for: an age range and "applies if…" lines.
struct AppliesIf: View {
    var ages: AgeRange?
    var conditions: [String]?
    @Environment(\.palette) private var p

    var body: some View {
        if ages != nil || !(conditions ?? []).isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                if let ages { Text("For \(formatAges(ages))") }
                ForEach(conditions ?? [], id: \.self) { Text("• \($0)") }
            }
            .font(TypeStyle.caption).foregroundStyle(p.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
