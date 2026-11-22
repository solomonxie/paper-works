import SwiftUI
import PaperWorksCore

/// Absolute and relative together — neither alone does the job.
struct DatePair: View {
    let date: CivilDate?
    var now: CivilDate = today()
    var precision: DatePrecision = .day
    /// A thing that happened: "13 years ago", never "late".
    var fact = false
    var lateRed = true
    @Environment(\.palette) private var p

    var body: some View {
        if let date {
            let relative = fact ? formatAgo(date, now: now) : formatRelative(date, now: now)
            let late = !fact && relative.hasSuffix("late")
            (Text(precision == .day ? formatDate(date) : formatPrecise(date, precision)).foregroundStyle(p.text)
                + Text(" · ").foregroundStyle(p.dim)
                + Text(relative).foregroundStyle(late && lateRed ? p.late : p.dim))
                .font(TypeStyle.caption)
        } else {
            Text("— · blocked").font(TypeStyle.caption).foregroundStyle(p.dim)
        }
    }
}
