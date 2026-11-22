import SwiftUI

struct ProgressBar: View {
    let done: Int
    let total: Int
    @Environment(\.palette) private var p

    var body: some View {
        let ratio = total == 0 ? 0 : Double(done) / Double(total)
        let complete = total > 0 && done == total
        HStack(spacing: Space.sm) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.hairline)
                    Rectangle().fill(complete ? p.done : p.accent).frame(width: g.size.width * ratio)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }
            .frame(height: 6)
            Text("\(done)/\(total)\(complete ? " ✓" : "")").font(TypeStyle.caption).foregroundStyle(p.dim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) done")
    }
}
