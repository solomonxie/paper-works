import SwiftUI
import PaperWorksCore

private let localInfo = "One copy a day, replaced on every change that day and kept \(KEEP_DAYS) days. What changed, and when, goes into a change log that is only ever added to. Both live in Files › Paper Works › Backups."
private let logInfo = "Every change, one line each: when, whose board, what happened. Added to, never rewritten or cleared — one file a year."
private let logShown = 30
private let icloudInfo = "Saved on every change in iCloud Drive › Paper Works, with scans and a latest.json. One dated copy a day, kept \(KEEP_DAYS) days. It survives deleting the app or losing the phone."

private struct Pending: Identifiable {
    let id = UUID()
    let label: String
    let plan: Plan
}

struct BackupsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var local: [String] = []
    @State private var cloud: [String] = []
    @State private var log: [String] = []
    @State private var openDay: String?
    @State private var pending: Pending?
    @State private var failure: String?

    private var now: CivilDate { model.now }

    private func dayLabel(_ day: String) -> String {
        day == now ? "Today" : day == addDays(now, -1) ? "Yesterday" : formatDate(day)
    }

    private func refresh() async {
        local = await BackupStorage.listBackups()
        if let text = try? await BackupStorage.readBackup(changeLogName(Date())) {
            log = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n", omittingEmptySubsequences: false)
                .suffix(logShown).reversed().map(String.init)
        } else { log = [] }
        cloud = model.settings.icloudBackup ? await BackupStorage.icloudList().filter { dailyDay($0) != nil } : []
    }

    private func restore(_ label: String, _ read: @escaping () async throws -> String) {
        Task {
            let text: String
            do { text = try await read() } catch { failure = "Can't open this copy\n\(error.localizedDescription)"; return }
            switch parseBackup(text) {
            case .failure(let e): failure = "Can't restore\n\(e)"
            case .ok(let plan): pending = Pending(label: label, plan: plan)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(TypeStyle.body).foregroundStyle(p.dim)
            .padding(.horizontal, Space.lg).frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        let days = groupSnapshots(local)
        let icloudOn = model.settings.icloudBackup
        ScrollView {
            VStack(spacing: 0) {
                SectionHeader("On this iPhone", count: days.reduce(0) { $0 + $1.names.count }, info: localInfo)
                if days.isEmpty {
                    note("The first copy is written with your next change.")
                } else {
                    Card {
                        Rows {
                            ForEach(days, id: \.day) { d in
                                VStack(spacing: 0) {
                                    ListRow(dayLabel(d.day), value: "\(d.names.count)",
                                            onPress: { openDay = openDay == d.day ? nil : d.day }, open: openDay == d.day)
                                    if openDay == d.day {
                                        ForEach(d.names, id: \.self) { n in
                                            ListRow("   \(snapshotTime(n))", onPress: {
                                                restore("\(dayLabel(d.day).lowercased()) \(snapshotTime(n).prefix(5))") {
                                                    try await BackupStorage.readBackup(n)
                                                }
                                            }, tone: .accent)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                SectionHeader("iCloud Drive", count: icloudOn ? cloud.count : nil, info: icloudInfo)
                if !icloudOn {
                    note("Off. Turn it on in Settings › Backup.")
                } else if cloud.isEmpty {
                    note("Nothing in iCloud yet.")
                } else {
                    Card {
                        Rows {
                            ForEach(cloud, id: \.self) { n in
                                let day = dailyDay(n) ?? ""
                                ListRow(dayLabel(day), value: day == now ? "replaced all day" : nil, onPress: {
                                    restore("iCloud, \(dayLabel(day).lowercased())") { try await BackupStorage.icloudRead(n) }
                                })
                            }
                        }
                    }
                }

                SectionHeader("Change log", info: logInfo) {
                    if !log.isEmpty { Text("(latest \(log.count))").font(TypeStyle.caption).foregroundStyle(p.dim) }
                }
                if log.isEmpty {
                    note("Changes appear here as you make them.")
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: Space.md) {
                            ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                                let f = line.components(separatedBy: "\t")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(f.first.map { String($0.prefix(16)) } ?? "") · \(f.count > 1 ? f[1] : "")")
                                        .font(TypeStyle.caption).foregroundStyle(p.dim)
                                    Text(f.count > 2 ? f[2] : "").font(TypeStyle.body).foregroundStyle(p.text)
                                }
                            }
                        }
                        .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                PWButton(title: "Show in Files") { Task { _ = await Files.openFolder(.backups) } }
                    .padding(.horizontal, Space.lg).padding(.top, Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Daily copies older than \(KEEP_DAYS) days are cleared automatically. The change log is kept.")
                    .font(TypeStyle.caption).foregroundStyle(p.faint).multilineTextAlignment(.center)
                    .padding(.horizontal, Space.xl).padding(.top, Space.lg)
            }
            .padding(.bottom, 80)
        }
        .background(p.bg)
        .navigationTitle("Backups")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.backups.lastLocal) { await refresh() }
        .task(id: model.settings.icloudBackup) { await refresh() }
        .onAppear { openDay = now }
        .alert(pending.map { "Restore from \($0.label)?" } ?? "", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { item in
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                Task {
                    await model.backupNow(tag: "before-restore")
                    model.replacePlan(item.plan)
                }
            }
        } message: { item in
            Text("It has \(item.plan.anchors.count) events, \(item.plan.tracks.count) plans. What you have now stays in Backups.")
        }
        .alert("Can't restore", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(failure ?? "") }
    }
}
