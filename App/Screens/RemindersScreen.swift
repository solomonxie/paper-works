import SwiftUI
import PaperWorksCore

private func hourName(_ h: Int) -> String {
    if h == 12 { return "noon" }
    return h > 12 ? "\(h - 12)pm" : "\(h)am"
}
private func leadOption(_ d: Int) -> PickerOption {
    let same = d == 0
    let label: String = same ? "same day" : String(d) + " days before"
    let short: String = same ? "same day" : String(d) + " days"
    return PickerOption(value: String(d), label: label, short: short)
}
private let leads: [PickerOption] = [0, 3, 7, 14, 30].map(leadOption)
private let days: [PickerOption] = (1...7).map { d in PickerOption(value: String(d), label: weekdayName(d)) }
private let hours: [PickerOption] = [7, 8, 9, 10, 12, 18, 20].map { h in
    PickerOption(value: String(h), label: hourName(h))
}

func capInfo(_ wanted: Int) -> String {
    "iOS holds at most 64 pending reminders per app. Your plan has \(wanted) open steps, so only the nearest ones are handed over; the queue refills each time you open the app or the plan changes. Nothing is lost — a step years out just has no alarm set yet."
}

struct RemindersScreen: View {
    private enum Open { case lead, day, hour }

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var open: Open?

    private func toggle(_ o: Open) { open = open == o ? nil : o }

    var body: some View {
        let s = model.settings
        let rem = model.reminderState
        ScrollView {
            VStack(spacing: 0) {
                Card {
                    UnfoldingPicker(label: "Remind me before start-by", value: String(s.leadDays), options: leads,
                                    open: open == .lead, onToggle: { toggle(.lead) }) { v in
                        model.updateSettings { $0.leadDays = Int(v) ?? 14 }
                        open = nil
                    }
                }
                .padding(.top, Space.lg)

                Card {
                    Rows {
                        ListRow("Weekly digest", chevron: false) {
                            Toggle("Weekly digest", isOn: Binding(
                                get: { model.settings.digestOn },
                                set: { v in model.updateSettings { $0.digestOn = v } })).labelsHidden()
                        }
                        if s.digestOn {
                            UnfoldingPicker(label: "Day", value: String(s.digestWeekday), options: days,
                                            open: open == .day, onToggle: { toggle(.day) }) { v in
                                model.updateSettings { $0.digestWeekday = Int(v) ?? 1 }
                                open = nil
                            }
                            UnfoldingPicker(label: "Time", value: String(s.digestHour), options: hours,
                                            open: open == .hour, onToggle: { toggle(.hour) }) { v in
                                model.updateSettings { $0.digestHour = Int(v) ?? 9 }
                                open = nil
                            }
                        }
                    }
                }
                .padding(.top, Space.lg)

                SectionHeader("Queued with iOS") {
                    Text("\(rem.queued)/\(PENDING_LIMIT)").font(TypeStyle.caption).foregroundStyle(p.dim)
                }
                Card {
                    VStack(alignment: .leading, spacing: Space.md) {
                        HStack(spacing: Space.md) {
                            ProgressBar(done: rem.queued, total: PENDING_LIMIT)
                            InfoPopover(text: capInfo(rem.wanted))
                        }
                        Text(rem.permission == .denied
                             ? "Reminders are turned off in iOS Settings, so nothing is queued."
                             : rem.through.map { "Through \(formatMonth($0)). The rest queue up as these fire." }
                                ?? "Nothing to queue yet.")
                            .font(TypeStyle.caption).foregroundStyle(p.dim)
                        PWButton(title: "Rebuild the queue") { Task { await model.syncNow() } }
                    }
                    .padding(Space.lg)
                }
            }
            .padding(.bottom, 80)
        }
        .background(p.bg)
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.refreshReminderState() }
    }
}
