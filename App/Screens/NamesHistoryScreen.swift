import SwiftUI
import PaperWorksCore

struct NamesHistoryScreen: View {
    let planId: String
    private enum Filter: String, CaseIterable { case all = "All", liked = "Liked", skipped = "Skipped" }

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var surname = ""
    @State private var surnameZh = ""
    @State private var loaded = false
    @State private var filter = Filter.all
    @State private var open: String?
    @State private var adding = false

    private func save(_ n: NameState) { model.saveNames(n, planId: planId) }

    var body: some View {
        let names = model.names(for: planId)
        let all = decisions(names).filter { nameById($0.id, names) != nil }
        let counts: [Filter: Int] = [.all: all.count, .liked: all.filter(\.liked).count, .skipped: all.filter { !$0.liked }.count]
        let shown = all.filter { filter == .all || $0.liked == (filter == .liked) }
        List {
            Section {
                LabeledContent("English") {
                    TextField("Xie", text: $surname).multilineTextAlignment(.trailing).submitLabel(.done)
                        .onSubmit { saveSurname() }.accessibilityLabel("English surname")
                }
                LabeledContent("中文") {
                    TextField("谢", text: $surnameZh).multilineTextAlignment(.trailing).submitLabel(.done)
                        .onSubmit { saveSurname() }.accessibilityLabel("Chinese surname")
                }
            } header: { Text("Surname") }
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text("\($0.rawValue) \(counts[$0] ?? 0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            if shown.isEmpty {
                Text(all.isEmpty ? "Swipe right to like a name, left to skip it. Your choices show up here."
                                 : "Nothing here yet.")
                    .font(TypeStyle.body).foregroundStyle(p.dim).listRowBackground(Color.clear)
            }
            Section {
                ForEach(shown, id: \.id) { d in
                    if let n = nameById(d.id, names) { row(n, d, names) }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !loaded { surname = names.surname; surnameZh = names.surnameZh; loaded = true } }
        .onDisappear { saveSurname() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add a name")
            }
        }
        .sheet(isPresented: $adding) {
            AddNameSheet(initialSet: names.set) { added in
                if let new = addName(model.names(for: planId), set: added.set, name: added.name, hanzi: added.hanzi, gender: added.gender,
                                     meaning: added.meaning, origin: added.origin) {
                    save(new)
                    if let id = new.history.last?.id { filter = .all; open = id }
                }
            }
        }
        .overlay { popup(names) }
    }

    @ViewBuilder private func popup(_ names: NameState) -> some View {
        if let id = open, let n = nameById(id, names) {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { dismiss() }
                NameCard(name: n, surname: n.set == .zh ? names.surnameZh : names.surname, editing: .constant(false),
                         liked: names.liked, onRelated: { rid in
                    Haptics.play(.light)
                    save(names.liked.contains(rid) ? forget(names, rid) : like(names, rid))
                }, onSurname: { _ in })
                    .frame(maxHeight: 520)
                    .padding(.horizontal, Space.lg)
                    .onTapGesture { dismiss() }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { dismiss() }
        }
    }

    private func dismiss() { withAnimation(.spring(duration: 0.3)) { open = nil } }

    private func row(_ n: BabyName, _ d: NameDecision, _ names: NameState) -> some View {
        let full = fullName(n, names)
        let flipAction = {
            Haptics.play(.light)
            withAnimation { save(flip(model.names(for: planId), n.id)) }
        }
        let removeAction = { withAnimation { save(forget(model.names(for: planId), n.id)) } }
        let showAction = { withAnimation(.spring(duration: 0.35, bounce: 0.25)) { open = n.id } }
        let isCustom = n.id.hasPrefix("custom:")
        return HStack(spacing: Space.md) {
            Button(action: flipAction) {
                Image(systemName: d.liked ? "heart.fill" : "heart")
                    .foregroundStyle(d.liked ? nameTint(.f) : p.dim)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            Button(action: showAction) {
                HStack(spacing: Space.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(full).font(TypeStyle.label).foregroundStyle(p.text).lineLimit(1)
                        if !n.meaning.isEmpty {
                            Text(n.meaning + (n.set == .zh ? n.source.map { " \u{00B7} " + sourceShort($0) } ?? "" : "")).font(TypeStyle.caption).foregroundStyle(p.dim).lineLimit(1)
                        }
                    }
                    Spacer(minLength: Space.sm)
                    Text(relativeDay(d.on)).font(TypeStyle.caption).foregroundStyle(p.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(full), \(d.liked ? "liked" : "skipped"), \(n.meaning), \(relativeDay(d.on))")
            .accessibilityHint("Shows the name card")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(isCustom ? "Delete" : "Remove", role: .destructive, action: removeAction)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: d.liked ? "Skip" : "Like", flipAction)
        .accessibilityAction(named: isCustom ? "Delete name" : "Remove from history", removeAction)
    }

    private func saveSurname() {
        var n = model.names(for: planId)
        let en = surname.trimmingCharacters(in: .whitespaces), zh = surnameZh.trimmingCharacters(in: .whitespaces)
        guard en != n.surname || zh != n.surnameZh else { return }
        n.surname = en; n.surnameZh = zh
        save(n)
    }
}

private struct NewName {
    var set = NameSet.en, name = "", hanzi = "", gender = NameGender.u, meaning = "", origin = ""
}

private struct AddNameSheet: View {
    let initialSet: NameSet
    let onSave: (NewName) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var p
    @State private var f = NewName()

    var body: some View {
        let match = bundledMatch(f.set, name: f.name, hanzi: f.hanzi)
        let empty = (f.set == .zh ? f.hanzi : f.name).trimmingCharacters(in: .whitespaces).isEmpty
        NavigationStack {
            Form {
                Section {
                    Picker("Language", selection: $f.set) { Text("English").tag(NameSet.en); Text("中文").tag(NameSet.zh) }
                        .pickerStyle(.segmented)
                    if f.set == .zh {
                        TextField("Characters", text: $f.hanzi)
                        TextField("Pinyin (optional)", text: $f.name).textInputAutocapitalization(.never)
                    } else {
                        TextField("Name", text: $f.name).textInputAutocapitalization(.words)
                    }
                    Picker("Gender", selection: $f.gender) {
                        Text("Girl").tag(NameGender.f); Text("Boy").tag(NameGender.m); Text("Either").tag(NameGender.u)
                    }
                    .pickerStyle(.segmented)
                }
                if let m = match {
                    Section {
                        Text("Already in the list \u{2014} will use its meaning and origin.").font(TypeStyle.caption).foregroundStyle(p.dim)
                        Text("\u{201C}\(m.meaning)\u{201D}" + (m.origin.map { " \u{00B7} \($0)" } ?? "")).font(TypeStyle.body)
                    }
                } else {
                    Section {
                        TextField("Meaning (optional)", text: $f.meaning)
                        TextField("Origin (optional)", text: $f.origin)
                    }
                }
            }
            .navigationTitle("Add a name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(f); dismiss() }.disabled(empty)
                }
            }
        }
        .onAppear { f.set = initialSet }
        .presentationDetents([.medium, .large])
    }
}
