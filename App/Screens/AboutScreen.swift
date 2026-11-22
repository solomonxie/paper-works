import SwiftUI

private let paragraphs = [
    "Add the events that bring paperwork (a move, a visa, a marriage, a new baby, a trip) and the app lays out every form and document in order, with the date to start each one so nothing lands late.",
    "Playbooks describe paperwork. They are not legal, immigration, tax or financial advice, and every one shows when it was last reviewed. Rules change; check the official source before relying on a step.",
    "Everything stays on this iPhone. No account, no server, no analytics. Nothing leaves unless you send it: a file you export, a daily copy in your own iCloud Drive, or events in your own calendar, each only if you turn it on.",
    "Place names come from GeoNames (geonames.org), under the Creative Commons Attribution 4.0 licence.",
    "Baby names: popularity and gender from US Social Security baby-name counts, Bible names from Hitchcock's Bible Names Dictionary (1869), both public domain. Meanings and origins are a short guide written for this list, not a dictionary.",
]

let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"

struct AboutScreen: View {
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Paper Works").font(TypeStyle.title).foregroundStyle(p.text)
                Text("Version \(appVersion)").font(TypeStyle.caption).foregroundStyle(p.dim)
                    .padding(.bottom, Space.lg)
                Card {
                    VStack(alignment: .leading, spacing: Space.md) {
                        ForEach(paragraphs, id: \.self) { Text($0).font(TypeStyle.body).foregroundStyle(p.text) }
                    }
                    .padding(Space.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, Space.xl).padding(.bottom, 80)
        }
        .background(p.bg)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
