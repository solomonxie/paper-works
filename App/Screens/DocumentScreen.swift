import SwiftUI
import UIKit
import PaperWorksCore

private enum OpenDate { case issued, expires }

struct DocumentScreen: View {
    let documentId: String
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var open: OpenDate?
    @State private var reveal = false
    @State private var scanImage: UIImage?
    @State private var scanFile: String?
    @State private var viewer = false
    @State private var addingScan = false
    @State private var forgetting = false
    @State private var editingNumber = false
    @State private var numberText = ""
    @State private var nothingToRedo = false

    private var doc: DocView? {
        documentViews(model.mine.documents, model.mine.view, model.mine.instances).first { $0.id == documentId }
    }

    var body: some View {
        Group {
            if let doc { content(doc) } else {
                Text("No step asks for this document any more.")
                    .font(TypeStyle.body).foregroundStyle(p.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(Space.xl)
            }
        }
        .background(p.bg.ignoresSafeArea())
        .navigationTitle(doc?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if let doc { ToolbarItem(placement: .topBarTrailing) { menu(doc) } } }
        .onDisappear { reveal = false }
        .task(id: doc?.record?.scanPath) { loadScan(doc?.record?.scanPath) }
        .confirmationDialog("Add a scan", isPresented: $addingScan, titleVisibility: .hidden) {
            Button("Take photo") { addScan(.camera) }
            Button("Photo library") { addScan(.photos) }
            Button("Files") { addScan(.files) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Forget \"\(doc?.name ?? "")\"?", isPresented: $forgetting) {
            Button("Cancel", role: .cancel) {}
            Button("Forget", role: .destructive) {
                if let doc {
                    if let scan = doc.record?.scanPath { Files.deleteScan(scan) }
                    model.forgetDocument(doc.id)
                    model.pop()
                }
            }
        } message: {
            Text("Its dates, number and scan are removed. Steps still list it.")
        }
        .alert("Document number", isPresented: $editingNumber) {
            TextField("Number", text: $numberText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let doc {
                    let v = numberText.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(doc) { $0.number = v.isEmpty ? nil : v }
                }
            }
        } message: {
            Text("Kept on this device only.")
        }
        .alert("Nothing to redo", isPresented: $nothingToRedo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No step in your plan produces this document.")
        }
        .fullScreenCover(isPresented: $viewer) {
            ZStack {
                Color.black.ignoresSafeArea()
                if let scanImage { Image(uiImage: scanImage).resizable().scaledToFit() }
            }
            .onTapGesture { viewer = false }
            .accessibilityLabel("Close scan")
            .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: actions

    private func record(_ doc: DocView) -> DocumentRecord { doc.record ?? DocumentRecord(id: documentId, name: doc.name) }

    private func save(_ doc: DocView, _ change: (inout DocumentRecord) -> Void) {
        var r = record(doc)
        change(&r)
        model.saveDocument(r)
    }

    private func loadScan(_ name: String?) {
        scanFile = name
        guard let name, let path = Files.scanPath(name) else { scanImage = nil; return }
        scanImage = UIImage(contentsOfFile: path)
    }

    private func addScan(_ source: ScanSource) {
        guard let doc else { return }
        Task {
            guard let name = await Files.shared.addScan(source) else { return }
            if let old = record(doc).scanPath { Files.deleteScan(old) }
            save(doc) { $0.scanPath = name; $0.issuedOn = $0.issuedOn ?? model.now }
        }
    }

    private func planRedo(_ doc: DocView) {
        let source = doc.clash?.source?.scheduled ?? doc.askedBy.first { $0.status == .done }?.scheduled
        let sourceTrack = doc.clash?.source?.trackId ?? doc.askedBy.first { $0.status == .done }?.trackId
        let consumer = doc.clash?.consumer ?? doc.neededBy
        guard let source, let consumer, sourceTrack == consumer.trackId,
              let id = model.planRedo(consumer.trackId, source.stepId, consumer.stepId)
        else { nothingToRedo = true; return }
        model.push(.step(instanceId: id))
    }

    private func menu(_ doc: DocView) -> some View {
        Menu {
            if scanImage != nil, let scanFile, let path = Files.scanPath(scanFile) {
                Button("Share…") { Task { _ = await Files.share(path) } }
            }
            Button(scanImage != nil ? "Replace scan" : "Add a scan") { addingScan = true }
            Button("Forget this document", role: .destructive) { forgetting = true }
        } label: {
            Text("⋯").font(TypeStyle.headline).foregroundStyle(p.accent)
        }
        .accessibilityLabel("More")
    }

    // MARK: body

    private func content(_ doc: DocView) -> some View {
        let now = model.now
        let r = record(doc)
        let expired = doc.expiresOn.map { $0 < now } ?? false
        let year = Int(now.prefix(4)) ?? 2026
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Card {
                    if let scanImage {
                        Button { viewer = true } label: {
                            Image(uiImage: scanImage).resizable().scaledToFill()
                                .frame(maxWidth: .infinity).frame(height: 180).clipped()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View scan")
                    } else {
                        Button("+ Add a scan or photo") { addingScan = true }
                            .buttonStyle(.pwPlain)
                            .padding(.vertical, Space.xl).frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, Space.sm)

                if expired, let expires = doc.expiresOn {
                    alertCard {
                        Text("⚠ Expired \(formatDate(expires))").font(TypeStyle.body).foregroundStyle(p.text)
                        PWButton(title: "Plan a redo", kind: .primary) { planRedo(doc) }
                    }
                } else if let clash = doc.clash {
                    alertCard {
                        Button { model.push(.step(instanceId: clash.consumer.instanceId)) } label: {
                            Text("⚠ Expires \(clash.gapDays) days before \"\(clash.consumer.title)\" needs it. ›")
                                .font(TypeStyle.body).foregroundStyle(p.text).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Warning: expires \(clash.gapDays) days before \(clash.consumer.title) needs it. Open that step")
                        PWButton(title: "Plan a redo") { planRedo(doc) }
                    }
                }

                Card {
                    Rows {
                        dateRow(doc, .issued, "issued", r.issuedOn ?? doc.issuedOn, empty: "not yet", year: year)
                        dateRow(doc, .expires, "expires", r.expiresOn ?? doc.expiresOn, empty: "doesn't expire", year: year)
                        ListRow("number", value: r.number == nil ? "add" : (reveal ? r.number : "••••••••"),
                                onPress: { numberText = r.number ?? ""; editingNumber = true }) {
                            if r.number != nil {
                                Button { reveal.toggle() } label: { Text(reveal ? "🙈" : "👁").font(TypeStyle.body) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(reveal ? "Hide number" : "Show number")
                            }
                        }
                        ListRow("kept in", value: "Files › Paper Works",
                                onPress: { Task { _ = await Files.openFolder(.scans) } })
                    }
                }
                .padding(.top, Space.md)

                if !doc.askedBy.isEmpty {
                    SectionHeader("Asked for by")
                    Card {
                        Rows(inset: Space.lg + 18 + Space.sm) {
                            ForEach(doc.askedBy, id: \.instanceId) { s in
                                StepRow(step: s.scheduled, now: now, subtitle: s.playbook.title, move: model.moves[s.instanceId]) {
                                    model.push(.step(instanceId: s.instanceId))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 120)
        }
    }

    @ViewBuilder private func dateRow(_ doc: DocView, _ key: OpenDate, _ label: String, _ value: CivilDate?,
                                      empty: String, year: Int) -> some View {
        let now = model.now
        ListRow(label, value: value.map(formatDate) ?? empty,
                onPress: { open = open == key ? nil : key }, open: open == key)
        if open == key {
            DateWheel(
                date: Binding(
                    get: { value ?? now },
                    set: { d in
                        save(doc) {
                            if key == .issued { $0.issuedOn = d } else { $0.expiresOn = d; $0.noExpiry = nil }
                        }
                    }),
                years: (year - 40)...(year + 20))
                .frame(maxWidth: .infinity)
            if key == .expires {
                Toggle("Doesn't expire", isOn: Binding(
                    get: { record(doc).noExpiry == true },
                    set: { none in
                        save(doc) {
                            $0.noExpiry = none ? true : nil
                            $0.expiresOn = none ? nil : (doc.expiresOn ?? now)
                        }
                    }))
                    .font(TypeStyle.body).foregroundStyle(p.text)
                    .padding(.horizontal, Space.lg).padding(.bottom, Space.md)
            }
        }
    }

    private func alertCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) { content() }
                .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
                .background(p.lateSoft)
        }
        .padding(.top, Space.md)
    }
}
