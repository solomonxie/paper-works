import SwiftUI
import PaperWorksCore

private let demoInfo = "A sample family's plan, in a store of its own: your plan isn't read, changed or backed up while it's on screen, and reminders and calendar stay as your plan left them. Turn it off to come straight back."
private let backupInfo = "Every change is saved as a snapshot on this iPhone and, with iCloud Drive on, in your own iCloud Drive › Paper Works: everything, scans and name picks included. A reinstalled app restores from it automatically. Export sends the same file anywhere through the share sheet."

/// "today 21:05" · "Sep 24" from a stamp or a daily file name.
private func snapshotLabel(_ stamp: String, _ now: CivilDate) -> String {
    let day = String(stamp.prefix(10))
    var when = day == now ? "today" : formatDate(day)
    if day != now, let r = when.range(of: #", \d{4}$"#, options: .regularExpression) { when.removeSubrange(r) }
    if let m = stamp.firstMatch(of: /T(\d{2})[-:](\d{2})/) { return "\(when) \(m.1):\(m.2)" }
    return when
}

private func hourLabel(_ h: Int) -> String { h == 12 ? "12pm" : h > 12 ? "\(h - 12)pm" : "\(h)am" }

private func openSystemSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var exporting = false
    @State private var importing: Plan?
    @State private var importError: String?
    @State private var confirmReset = false

    private func binding<T>(_ get: @escaping (Settings) -> T, _ set: @escaping (inout Settings, T) -> Void) -> Binding<T> {
        Binding(get: { get(model.settings) }, set: { v in model.updateSettings { set(&$0, v) } })
    }

    private func export() async {
        exporting = true
        defer { exporting = false }
        let text = serializePlan(model.plan, model.now)
        let name = "Paper Works backup \(model.now).json"
        guard let path = try? Files.writeTemp(name, text: text), await Files.share(path) else { return }
        let bytes = text.count
        model.updateSettings { $0.lastExport = LastExport(on: model.now, bytes: bytes) }
    }

    private func pickImport() async {
        guard let path = await Files.shared.pickFile(["public.json", "public.plain-text"]) else { return }
        guard let text = try? Files.readText(path) else { importError = "This file can't be read."; return }
        switch parseBackup(text) {
        case .failure(let e): importError = e
        case .ok(let plan): importing = plan
        }
    }

    var body: some View {
        let s = model.settings
        let rem = model.reminderState
        let b = model.backups
        let now = model.now
        let denied = rem.permission == .denied
        let blocked = b.icloudStatus == .driveOff || b.icloudStatus == .notEntitled
        let icloudDetail = b.icloudStatus == .driveOff ? "iCloud Drive is off for this iPhone."
            : b.icloudStatus == .notEntitled ? "Not available in this build."
            : b.icloudStatus == .notReady ? "iCloud isn't ready yet. Data stays on this iPhone for now."
            : !s.icloudBackup ? "Off: your data won't survive deleting the app."
            : b.lastICloud != nil ? "Saved automatically · last \(snapshotLabel(b.lastICloud!, now))"
            : "Saved automatically on every change. Turning it off means data won't survive deleting the app."
        let stale = model.playbooks.filter { isStale($0, now) }.count

        ScrollView {
            VStack(spacing: 0) {
                Text("Settings").font(TypeStyle.title).foregroundStyle(p.text)
                    .padding(.horizontal, Space.lg).padding(.top, Space.xxl)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)

                SectionHeader("Reminders", info: capInfo(rem.wanted))
                if denied {
                    HStack {
                        Text("⚠ Turned off in iOS Settings.").font(TypeStyle.body).foregroundStyle(p.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PWButton(title: "Open Settings", kind: .plain, action: openSystemSettings)
                    }
                    .padding(Space.md).padding(.horizontal, Space.xs)
                    .background(p.lateSoft).clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .padding(.horizontal, Space.lg).padding(.bottom, Space.sm)
                } else {
                    Text("Only the steps you haven't started.").font(TypeStyle.caption).foregroundStyle(p.dim)
                        .padding(.horizontal, Space.lg).padding(.bottom, Space.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Card {
                    Rows {
                        ListRow("Remind me before start-by",
                                value: s.leadDays == 0 ? "same day" : "\(s.leadDays) days",
                                onPress: { model.push(.reminders) })
                            .disabled(denied)
                        ListRow("Weekly digest",
                                value: s.digestOn ? "\(weekdayName(s.digestWeekday).prefix(3)) \(hourLabel(s.digestHour))" : "off",
                                onPress: { model.push(.reminders) })
                            .disabled(denied)
                        ListRow("Nearest reminders queued", value: "\(rem.queued)/\(PENDING_LIMIT)",
                                onPress: { model.push(.reminders) })
                    }
                }

                SectionHeader("Backup", info: backupInfo)
                Card {
                    ListRow("On this iPhone",
                            value: b.lastLocal.map { "\(snapshotLabel($0, now)) · \(b.localCount)" } ?? "next change",
                            onPress: { model.push(.backups) })
                    PWDivider()
                    ListRow("iCloud Drive", detail: icloudDetail, chevron: false) {
                        Toggle("iCloud Drive backup", isOn: binding(\.icloudBackup) { $0.icloudBackup = $1 })
                            .labelsHidden().disabled(!s.icloudBackup && blocked)
                    }
                    if blocked {
                        PWButton(title: "Open Settings", kind: .plain, action: openSystemSettings)
                            .padding(.horizontal, Space.lg).padding(.bottom, Space.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    PWDivider()
                    ListRow("Last export",
                            value: s.lastExport.map { "\(formatDate($0.on)) · \(max(1, Int((Double($0.bytes) / 1024).rounded()))) KB" } ?? "never",
                            chevron: false)
                    HStack(spacing: Space.md) {
                        PWButton(title: exporting ? "Exporting…" : "Export…") { Task { await export() } }
                            .disabled(exporting).frame(maxWidth: .infinity)
                        PWButton(title: "Import…") { Task { await pickImport() } }
                            .disabled(exporting).frame(maxWidth: .infinity)
                    }
                    .padding(Space.lg).padding(.top, -Space.sm)
                }

                SectionHeader("Playbooks")
                Card {
                    Rows {
                        ListRow("Sources",
                                value: model.plan.playbooks.isEmpty ? "bundled only" : "bundled + \(model.plan.playbooks.count) yours",
                                onPress: { model.push(.sources) })
                        ListRow("Check review dates", value: stale > 0 ? "\(stale) old" : "all current",
                                onPress: { model.push(.sources) }, tone: stale > 0 ? .late : .normal)
                    }
                }

                Card {
                    Rows {
                        ListRow("Calendar export",
                                detail: rem.calendarDenied && s.calendarMirror
                                    ? "Calendar access is off in iOS Settings."
                                    : "Start-by dates in a \"Paper Works\" calendar", chevron: false) {
                            Toggle("Calendar export", isOn: binding(\.calendarMirror) { $0.calendarMirror = $1 }).labelsHidden()
                        }
                        ListRow("Haptics", chevron: false) {
                            Toggle("Haptics", isOn: binding(\.haptics) { $0.haptics = $1 }).labelsHidden()
                        }
                    }
                }
                .padding(.top, Space.xl)

                Card { ListRow("About", onPress: { model.push(.about) }) }
                    .padding(.top, Space.xl)
                Text("Paper Works \(appVersion) · not advice").font(TypeStyle.caption).foregroundStyle(p.dim)
                    .padding(Space.lg)

                SectionHeader("Demo", info: demoInfo)
                Card {
                    Rows {
                        ListRow("Demo data",
                                detail: model.demoOn ? "Showing a sample plan, not yours." : "Show a sample plan instead of yours",
                                chevron: false) {
                            Toggle("Demo data", isOn: Binding(get: { model.demoOn },
                                                              set: { v in Task { await model.setDemo(v) } }))
                                .labelsHidden().disabled(model.demoSwitching)
                        }
                        if model.demoOn {
                            ListRow("Reset demo data", onPress: { confirmReset = true }, chevron: false, tone: .late)
                        }
                    }
                }
            }
            .padding(.bottom, 80 + Space.lg)
        }
        .background(p.bg)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.refreshReminderState(); model.refreshBackupState() }
        .alert("Replace your plan?", isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
               presenting: importing) { plan in
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) { model.replacePlan(plan) }
        } message: { plan in
            Text("This file has \(plan.anchors.count) events and \(plan.tracks.count) plans. Your current \(model.plan.anchors.count) events and \(model.plan.tracks.count) plans are overwritten.")
        }
        .alert("Can't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(importError ?? "") }
        .alert("Reset demo data?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { model.resetDemo() }
        } message: { Text("Back to the sample plan as first installed. Your own plan is not touched.") }
    }
}
