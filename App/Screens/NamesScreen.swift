import SwiftUI
import PaperWorksCore

let nameTags = ["popular", "rare", "bible", "saint", "nature", "flower", "virtue", "mythology", "royal", "literary", "celestial", "gem"]
let nameTagsZh: [String: String] = [
    "popular": "热门", "bible": "圣经", "poetry": "诗词", "solarterm": "节气", "idiom": "成语", "historical": "历史", "famous": "名人",
    "nature": "自然", "virtue": "品德", "celestial": "星辰", "flower": "花卉", "gem": "珠玉", "literary": "文雅", "classic": "经典", "modern": "现代",
]

func tagLabel(_ t: String, _ set: NameSet) -> String {
    if set == .zh, let z = nameTagsZh[t] { return z }
    return t.prefix(1).uppercased() + t.dropFirst()
}

func genderLabel(_ g: NameGender) -> String {
    switch g { case .f: "Girl"; case .m: "Boy"; case .u: "Either" }
}


struct NamesScreen: View {
    let planId: String
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p
    @State private var last: NameState?
    @State private var lastCard: String?
    @State private var pinned: String?
    @State private var popup: String?
    @State private var editingSurname = false
    @State private var drag: CGFloat = 0
    @State private var flyOff: CGFloat = 0
    @State private var showFilters = false
    @State private var changingEvent = false
    @State private var showAllOrigins = false
    @AppStorage("names.mode") private var listMode = false

    /// A tapped list row: its card over the list, with the same like/skip buttons and swipes as card mode.
    @ViewBuilder private func listPopup(_ names: NameState) -> some View {
        if let id = popup, let n = nameById(id, names) {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { closePopup() }
                VStack(spacing: Space.md) {
                    NameCard(name: n, surname: n.set == .zh ? names.surnameZh : names.surname, editing: .constant(false),
                             liked: names.liked, onRelated: { rid in
                        Haptics.play(.light)
                        save(names.liked.contains(rid) ? forget(names, rid) : like(names, rid))
                    }, onSurname: { _ in })
                        .frame(maxHeight: 520)
                        .offset(x: drag + flyOff)
                        .rotationEffect(.degrees(Double(drag + flyOff) / 25))
                        .overlay(alignment: drag > 0 ? .topLeading : .topTrailing) { stamp }
                        .gesture(popupSwipe(n))
                    HStack(spacing: Space.xl) {
                        roundButton("xmark", size: 64, color: p.late, label: "Skip") { popupDecide(n, liked: false) }
                        roundButton("heart.fill", size: 64, color: nameTint(.f), label: "Like") { popupDecide(n, liked: true) }
                    }
                }
                .padding(.horizontal, Space.lg)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { closePopup() }
        }
    }

    private func popupSwipe(_ n: BabyName) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) || drag != 0 else { return }
                drag = v.translation.width
            }
            .onEnded { v in
                if abs(v.translation.width) > 100 || abs(v.predictedEndTranslation.width) > 250 {
                    popupDecide(n, liked: v.translation.width > 0)
                } else {
                    withAnimation(.spring(duration: 0.3, bounce: 0.3)) { drag = 0 }
                }
            }
    }

    /// Flies the card off, records the decision, and drops back to the list.
    private func popupDecide(_ n: BabyName, liked: Bool) {
        withAnimation(.spring(duration: 0.22, bounce: 0)) { flyOff = liked ? 500 : -500 } completion: {
            rowDecide(n, liked: liked)
            popup = nil
            drag = 0; flyOff = 0
        }
    }

    private func save(_ n: NameState) { model.saveNames(n, planId: planId) }
    private func closePopup() { withAnimation(.spring(duration: 0.3)) { popup = nil } }

    var body: some View {
        let names = model.names(for: planId)
        let cards = deck(NAMES, names)
        let card = pinned.flatMap { NAMES_BY_ID[$0] } ?? cards.first
        let rest = cards.filter { $0.id != card?.id }
        VStack(spacing: Space.md) {
            filterBar(names)
            if listMode {
                NamesListView(cards: cards, header: listHeader(names, cards.count), surname: names.set == .zh ? names.surnameZh : names.surname, liked: names.liked,
                              onLike: { rowDecide($0, liked: true) }, onSkip: { rowDecide($0, liked: false) },
                              onOpen: { popup = $0.id })
            } else if let card {
                ZStack {
                    if let next = rest.first {
                        ghost(next, depth: 2).opacity(rest.count > 1 ? 1 : 0)
                        ghost(next, depth: 1)
                    }
                    NameCard(name: card, surname: names.set == .zh ? names.surnameZh : names.surname, editing: $editingSurname, liked: names.liked, onRelated: { toggleRelated($0, card: card) }) { s in
                        var n = names
                        if n.set == .zh { n.surnameZh = s } else { n.surname = s }
                        save(n)
                    }
                    .id(card.id)
                    .offset(x: drag + flyOff)
                    .rotationEffect(.degrees(Double(drag + flyOff) / 25))
                    .overlay(alignment: drag > 0 ? .topLeading : .topTrailing) { stamp }
                    .gesture(swipe(card))
                    .transition(.identity)
                }
                .padding(.horizontal, Space.lg).padding(.top, Space.xs)
                actions
            } else {
                Spacer(minLength: 0)
                Card {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("That's every name for these filters.").font(TypeStyle.body).foregroundStyle(p.text)
                        Text("\(fitting(NAMES, names).formatted()) seen · \(names.liked.count) liked")
                            .font(TypeStyle.caption).foregroundStyle(p.dim)
                        PWButton(title: "Go through the skipped ones again", kind: .plain) {
                            update(reshuffle(NAMES, names))
                        }
                    }
                    .padding(Space.lg)
                }
                .padding(.horizontal, Space.lg)
                Spacer(minLength: 0)
            }
        }
        .padding(.top, Space.sm)
        .background(p.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .background(PopGestureDisabler())
        .overlay { listPopup(names) }
        .sheet(isPresented: $showFilters) { filterSheet.presentationDetents([.medium, .large]) }
        .sheet(isPresented: $changingEvent) {
            EventPicker(current: model.settings.toolPlans.first { $0.id == planId }?.anchorId) {
                model.setToolPlanEvent(planId, anchorId: $0)
            } onNew: { model.push(.anchorEdit(anchorId: nil, kind: "baby-due")) }
                .presentationDetents([.medium, .large])
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                let tp = model.settings.toolPlans.first { $0.id == planId }
                VStack(spacing: 0) {
                    Text("Baby names").font(TypeStyle.label).foregroundStyle(p.text)
                    if let sub = tp.flatMap({ model.eventSubtitle($0) }) {
                        Text(sub).font(TypeStyle.caption).foregroundStyle(p.dim)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Change event…", systemImage: "calendar") { changingEvent = true }
                    Button("Remove plan", systemImage: "trash", role: .destructive) { model.removeToolPlan(planId); model.pop() }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Plan options")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { withAnimation { listMode.toggle() } } label: { 
                    HStack(spacing: 4) {
                        Image(systemName: listMode ? "rectangle.stack" : "list.bullet")
                        Text(cards.count.formatted()).font(TypeStyle.caption.weight(.semibold)).monospacedDigit()
                    }
                }
                    .accessibilityLabel(listMode ? "Card mode" : "List mode")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.namesHistory(planId: planId)) { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("History")
                    .accessibilityHint("Opens the names you liked and skipped")
            }
        }
    }

    private func ghost(_ n: BabyName, depth: Int) -> some View {
        let d = CGFloat(depth)
        return RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(nameTint(n.gender).opacity(0.35 - 0.1 * d))
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(p.card))
            .scaleEffect(1 - 0.04 * d)
            .rotationEffect(.degrees(depth == 1 ? 2.5 : -2.5))
            .offset(y: 12 * d)
    }

    private var actions: some View {
        HStack(spacing: Space.xl) {
            roundButton("xmark", size: 64, color: p.late, label: "Skip") { decide(false) }
            roundButton("arrow.uturn.backward", size: 44, color: p.dim, label: "Undo") {
                if let l = last { withAnimation(.spring(duration: 0.3)) { save(l) } }
                pinned = lastCard
                last = nil
            }
            .disabled(last == nil).opacity(last == nil ? 0.35 : 1)
            roundButton("heart.fill", size: 64, color: nameTint(.f), label: "Like") { decide(true) }
        }
        .padding(.top, Space.md).padding(.bottom, Space.lg)
    }

    private func roundButton(_ icon: String, size: CGFloat, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(color)
                .frame(width: size, height: size)
                .background(Circle().fill(p.card))
                .overlay(Circle().stroke(color.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var stamp: some View {
        let strength = min(abs(drag) / 100, 1)
        let like = drag > 0
        Text(like ? "LIKE" : "SKIP")
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .foregroundStyle(like ? nameTint(.f) : p.dim)
            .padding(.horizontal, Space.md).padding(.vertical, Space.xs)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(like ? nameTint(.f) : p.dim, lineWidth: 3))
            .rotationEffect(.degrees(like ? -12 : 12))
            .padding(Space.xl)
            .opacity(strength)
            .allowsHitTesting(false)
    }

    private func swipe(_ card: BabyName) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) || drag != 0 else { return }
                drag = v.translation.width
            }
            .onEnded { v in
                let dx = v.predictedEndTranslation.width
                if abs(v.translation.width) > 100 || abs(dx) > 250 {
                    fling(liked: v.translation.width > 0)
                } else {
                    withAnimation(.spring(duration: 0.3, bounce: 0.3)) { drag = 0 }
                }
            }
    }

    private func fling(liked: Bool) {
        withAnimation(.spring(duration: 0.22, bounce: 0)) { flyOff = liked ? 500 : -500 } completion: {
            decide(liked, animated: false)
            drag = 0; flyOff = 0
        }
    }

    private func decide(_ liked: Bool, animated: Bool = true) {
        let names = model.names(for: planId)
        guard let card = pinned.flatMap({ NAMES_BY_ID[$0] }) ?? deck(NAMES, names).first else { return }
        if animated, flyOff == 0 { fling(liked: liked); return }
        last = names
        lastCard = card.id
        pinned = nil
        Haptics.play(liked ? .success : .light)
        save(liked ? like(names, card.id) : pass(names, card.id))
    }

    private func listHeader(_ names: NameState, _ count: Int) -> String {
        let g = switch names.gender { case .f: "Girls"; case .m: "Boys"; case .all: "Both" }
        let f = (names.tags + names.origins + names.initials).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: ", ")
        return (["\(count.formatted()) names", g] + (f.isEmpty ? [] : [f])).joined(separator: " · ")
    }

    private func rowDecide(_ card: BabyName, liked: Bool) {
        let names = model.names(for: planId)
        last = names
        lastCard = card.id
        Haptics.play(liked ? .success : .light)
        withAnimation { save(liked ? like(names, card.id) : pass(names, card.id)) }
    }

    private func update(_ n: NameState) { last = nil; pinned = nil; save(n) }

    private func toggleRelated(_ id: String, card: BabyName?) {
        guard let card else { return }
        let names = model.names(for: planId)
        pinned = card.id
        Haptics.play(.light)
        save(names.liked.contains(id) ? forget(names, id) : like(names, id))
    }

    private func filterBar(_ names: NameState) -> some View {
        let count = names.tags.count + names.origins.count + names.initials.count
        return VStack(spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                ForEach([(GenderPick.f, "Girls", "figure.stand.dress", nameTint(.f)), (.m, "Boys", "figure.stand", nameTint(.m)),
                         (.all, "Both", "sparkles", nameTint(.u))], id: \.0) { g in
                    toggle(g.1, icon: g.2, tint: g.3, on: names.gender == g.0) { var n = names; n.gender = g.0; update(n) }
                }
            }
            HStack(spacing: Space.sm) {
                HStack(spacing: 2) {
                    ForEach([(NameSet.en, "English"), (.zh, "中文")], id: \.0) { o in
                        let on = names.set == o.0
                        Button { var n = names; n.set = o.0; n.tags = []; n.origins = []
                            n.initials = n.initials.filter { initialCounts(NAMES, set: o.0, gender: n.gender)[$0] != nil }
                            update(n) } label: {
                            Text(o.1).font(TypeStyle.caption.weight(.semibold))
                                .foregroundStyle(on ? .white : p.dim)
                                .padding(.horizontal, Space.md).padding(.vertical, 7)
                                .background(Capsule().fill(on ? p.accent : .clear))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(2).background(Capsule().fill(p.card))
                Spacer(minLength: 0)
                Button { showFilters = true } label: {
                    Label(count > 0 ? "Filters · \(count)" : "Filters", systemImage: "line.3.horizontal.decrease")
                        .font(TypeStyle.caption.weight(.semibold))
                        .foregroundStyle(count > 0 ? .white : p.text)
                        .padding(.horizontal, Space.md).padding(.vertical, 9)
                        .background(Capsule().fill(count > 0 ? p.accent : p.card))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens tag and origin filters")
            }
        }
        .padding(.horizontal, Space.lg)
    }

    private func toggle(_ label: String, icon: String, tint: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon).font(TypeStyle.caption.weight(.semibold))
                .foregroundStyle(on ? .white : tint)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(Capsule().fill(on ? tint : tint.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var filterSheet: some View {
        let names = model.names(for: planId)
        let pool = NAMES.filter { matches($0, NamePrefs(set: names.set, gender: names.gender, tags: [], origins: [], initials: [])) }
        let tagCount: (String) -> Int = { t in
            pool.filter { n in
                switch t {
                case "popular" where names.set == .en: n.rank.map { $0 <= POPULAR_RANK } ?? false
                case "rare" where names.set == .en: n.rank.map { $0 > RARE_RANK } ?? true
                default: n.tags.contains(t)
                }
            }.count
        }
        let tags: [String]
        if names.set == .zh {
            let present = Set(pool.flatMap(\.tags)).union(names.tags).filter { nameTagsZh[$0] != nil }
            let order = Array(nameTagsZh.keys)
            let sorted = present.filter { $0 != "popular" }.sorted {
                tagCount($0) != tagCount($1) ? tagCount($0) > tagCount($1) : (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0)
            }
            tags = (present.contains("popular") ? ["popular"] : []) + sorted
        } else {
            tags = nameTags.filter { $0 == "popular" || $0 == "rare" } + nameTags.filter { $0 != "popular" && $0 != "rare" }.sorted { tagCount($0) > tagCount($1) }
        }
        var originCounts: [String: Int] = [:]
        for n in pool { if let o = n.origin, !o.isEmpty { originCounts[o, default: 0] += 1 } }
        let letterCounts = initialCounts(NAMES, set: names.set, gender: names.gender)
        let letters = (65...90).map { String(UnicodeScalar($0)!) }.filter { letterCounts[$0] != nil || names.initials.contains($0) }
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("Tags (any of them)").font(TypeStyle.label).foregroundStyle(p.dim)
                    Flow {
                        ForEach(tags, id: \.self) { t in
                            chip(tagLabel(t, names.set), count: tagCount(t), on: names.tags.contains(t)) {
                                var n = names; n.tags = n.tags.toggled(t); update(n)
                            }
                        }
                    }
                    Text("First letter (any of)").font(TypeStyle.label).foregroundStyle(p.dim)
                    Flow(spacing: 6) {
                        ForEach(letters, id: \.self) { l in
                            chip(l, count: letterCounts[l] ?? 0, on: names.initials.contains(l)) { var n = names; n.initials = n.initials.toggled(l); update(n) }
                        }
                    }
                    if names.set == .en {
                        Text("Origin (any of)").font(TypeStyle.label).foregroundStyle(p.dim)
                        Flow {
                            ForEach(originOptions(names, originCounts), id: \.self) { o in
                                chip(o, count: originCounts[o] ?? 0, on: names.origins.contains(o)) { var n = names; n.origins = n.origins.toggled(o); update(n) }
                            }
                        }
                        if !showAllOrigins {
                            Button("More origins…") { showAllOrigins = true }.font(TypeStyle.caption).foregroundStyle(p.accent)
                        }
                    }
                }
                .padding(Space.lg).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(p.bg.ignoresSafeArea())
            .navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { var n = names; n.tags = []; n.origins = []; n.initials = []; update(n) }
                        .disabled(names.tags.isEmpty && names.origins.isEmpty && names.initials.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { showFilters = false } }
            }
        }
    }

    private func originOptions(_ names: NameState, _ counts: [String: Int]) -> [String] {
        let ranked = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        let all = Array(ranked.prefix(showAllOrigins ? 60 : 12))
        return all + names.origins.filter { !all.contains($0) }
    }

    private func chip(_ label: String, count: Int? = nil, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                if let count { Text("\(count)").foregroundStyle(on ? p.onAccent.opacity(0.7) : p.faint) }
            }
            .font(TypeStyle.caption)
                .foregroundStyle(on ? p.onAccent : p.text)
                .padding(.horizontal, Space.md).padding(.vertical, 6)
                .background(Capsule().fill(on ? p.accent : p.card))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private extension Array where Element: Equatable {
    func toggled(_ x: Element) -> [Element] {
        var a = self
        if let i = a.firstIndex(of: x) { a.remove(at: i) } else { a.append(x) }
        return a
    }
}

private struct PopGestureDisabler: UIViewControllerRepresentable {
    final class VC: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
    func makeUIViewController(context: Context) -> VC { VC() }
    func updateUIViewController(_ vc: VC, context: Context) {}
}

func nameTint(_ g: NameGender) -> Color {
    switch g {
    case .f: Color(red: 0.95, green: 0.40, blue: 0.48)
    case .m: Color(red: 0.12, green: 0.62, blue: 0.78)
    case .u: Color(red: 0.93, green: 0.62, blue: 0.14)
    }
}

private func nameTint2(_ g: NameGender) -> Color {
    switch g {
    case .f: Color(red: 1.0, green: 0.62, blue: 0.40)
    case .m: Color(red: 0.25, green: 0.42, blue: 0.92)
    case .u: Color(red: 0.55, green: 0.38, blue: 0.88)
    }
}

private let tagStyle: [String: (String, Color)] = [
    "bible": ("book", .brown), "saint": ("sparkles", .yellow), "nature": ("leaf", .green), "flower": ("camera.macro", .pink),
    "virtue": ("heart.circle", .orange), "mythology": ("bolt", .purple), "royal": ("crown", .indigo),
    "literary": ("text.book.closed", .teal), "celestial": ("moon.stars", .blue), "gem": ("diamond", .cyan),
    "classic": ("building.columns", .brown), "modern": ("sparkle", .mint),
    "poetry": ("text.book.closed", .teal), "solarterm": ("sun.haze", .orange), "idiom": ("character.book.closed", .indigo),
    "popular": ("flame", .red), "historical": ("scroll", .brown), "famous": ("star", .yellow),
    CUSTOM_TAG: ("person.fill", .gray),
]

private struct Flow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal.width ?? 300, subviews).size
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (v, o) in zip(subviews, layout(b.width, subviews).origins) {
            v.place(at: CGPoint(x: b.minX + o.x, y: b.minY + o.y), proposal: .unspecified)
        }
    }
    private func layout(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, w: CGFloat = 0
        var origins: [CGPoint] = []
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += row + spacing; row = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += s.width + spacing; row = max(row, s.height); w = max(w, x - spacing)
        }
        return (CGSize(width: w, height: y + row), origins)
    }
}

struct NameCard: View {
    let name: BabyName
    let surname: String
    @Binding var editing: Bool
    let liked: [String]
    let onRelated: (String) -> Void
    let onSurname: (String) -> Void
    @Environment(\.palette) private var p
    @State private var draft = ""
    @State private var showAllRelated = false
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(alignment: .leading, spacing: Space.md) {
            Spacer(minLength: 0)
            if let hanzi = name.hanzi {
                Text(surname + hanzi).font(.system(size: 80, weight: .bold, design: .rounded)).foregroundStyle(p.text)
                    .lineLimit(1).minimumScaleFactor(0.4)
                Text(name.name).font(.system(.title2, design: .rounded).weight(.medium)).foregroundStyle(p.dim)
                surnameView
            } else {
                Text(name.name).font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundStyle(p.text)
                    .lineLimit(1).minimumScaleFactor(0.4)
                surnameView
            }
            Text("\u{201C}\(name.meaning)\u{201D}").font(.system(.title3, design: .serif).italic()).foregroundStyle(p.text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            sourceQuoteView
            related
            Spacer(minLength: 0)
            Flow {
                pill(genderIcon, genderLabel(name.gender), nameTint(name.gender))
                if name.set == .en {
                    if let o = name.origin, !o.isEmpty { pill("globe", o, nil) }
                    if let l = name.language, !l.isEmpty { pill("text.bubble", l, nil) }
                    if let r = rankLabel(name) { popularity(r) }
                    if let y = name.peak { pill("calendar", "Peak \(y)", nil) }
                }
                ForEach(name.tags, id: \.self) { t in
                    let st = tagStyle[t] ?? ("tag", p.accent)
                    pill(st.0, tagLabel(t, name.set), st.1)
                }
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            shape.fill(p.card)
                .overlay(shape.fill(LinearGradient(colors: [nameTint(name.gender).opacity(0.30), nameTint2(name.gender).opacity(0.10)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)))
        )
        .clipShape(shape)
        .shadow(color: nameTint(name.gender).opacity(0.3), radius: 18, y: 8)
    }

    @ViewBuilder private var sourceQuoteView: some View {
        if let src = name.source, !src.isEmpty {
            let quote = sourceQuote(src)
            HStack(alignment: .top, spacing: Space.sm) {
                Rectangle().fill(p.dim.opacity(0.5)).frame(width: 2)
                VStack(alignment: .leading, spacing: 2) {
                    if let quote {
                        Text("\u{300C}\(quote)\u{300D}").font(.system(.callout, design: .serif)).foregroundStyle(p.text.opacity(0.8))
                        Text("\u{2014} \(sourceShort(src))").font(.system(.footnote, design: .serif)).foregroundStyle(p.dim)
                    } else {
                        Text(src).font(.system(.callout, design: .serif)).foregroundStyle(p.text.opacity(0.8))
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var related: some View {
        let all = (NAME_VARIANTS[nameGroup(name.id)] ?? []).filter { $0.id != name.id }
        if !all.isEmpty {
            let shown = showAllRelated ? all : Array(all.prefix(10))
            let n = all.filter { liked.contains($0.id) }.count
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text("Related").font(TypeStyle.label).foregroundStyle(p.dim)
                    if n > 0 {
                        Text("\(n) liked").font(TypeStyle.caption.weight(.semibold)).foregroundStyle(nameTint(.f))
                            .padding(.horizontal, Space.sm).padding(.vertical, 2)
                            .background(Capsule().fill(nameTint(.f).opacity(0.15)))
                    }
                }
                Flow(spacing: 6) {
                    ForEach(shown) { v in
                        let on = liked.contains(v.id)
                        Button { onRelated(v.id) } label: {
                            Text(v.name).font(TypeStyle.caption.weight(.medium))
                                .foregroundStyle(on ? nameTint(.f) : p.text)
                                .padding(.horizontal, Space.md).padding(.vertical, 6)
                                .background(Capsule().fill(on ? nameTint(.f).opacity(0.2) : p.text.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityHint("Likes this name instead")
                    }
                    if all.count > shown.count {
                        Button { withAnimation { showAllRelated = true } } label: {
                            Text("+\(all.count - shown.count) more").font(TypeStyle.caption.weight(.medium)).foregroundStyle(p.accent)
                                .padding(.horizontal, Space.md).padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var genderIcon: String {
        switch name.gender { case .f: "figure.stand.dress"; case .m: "figure.stand"; case .u: "sparkles" }
    }

    private func pill(_ icon: String, _ text: String, _ tint: Color?) -> some View {
        Label(text, systemImage: icon).font(TypeStyle.caption.weight(.medium))
            .foregroundStyle(tint ?? p.text)
            .padding(.horizontal, Space.md).padding(.vertical, 6)
            .background(Capsule().fill((tint ?? p.text).opacity(0.14)))
    }

    private func popularity(_ label: String) -> some View {
        let frac = name.rank.map { r in r > RARE_RANK ? 0.04 : max(0.06, 1 - log10(Double(max(r, 1))) / log10(Double(RARE_RANK))) } ?? 0.04
        return HStack(spacing: 6) {
            Image(systemName: "chart.bar")
            Text(label)
            Capsule().fill(p.text.opacity(0.15)).frame(width: 34, height: 5)
                .overlay(alignment: .leading) { Capsule().fill(nameTint(name.gender)).frame(width: 34 * frac, height: 5) }
        }
        .font(TypeStyle.caption.weight(.medium)).foregroundStyle(p.text)
        .padding(.horizontal, Space.md).padding(.vertical, 6)
        .background(Capsule().fill(p.text.opacity(0.14)))
    }

    @ViewBuilder private var surnameView: some View {
        if editing {
            TextField("Surname", text: $draft)
                .font(.system(.title, design: .rounded).weight(.semibold)).foregroundStyle(p.dim)
                .focused($focused).submitLabel(.done)
                .onSubmit { done() }
                .onChange(of: focused) { _, f in if !f && editing { done() } }
                .accessibilityLabel("Surname")
        } else {
            Button {
                draft = surname; editing = true; focused = true
            } label: {
                if surname.isEmpty {
                    Text(name.hanzi == nil ? "+ Surname" : "+ 姓").font(TypeStyle.label).foregroundStyle(p.accent)
                } else {
                    Text(surname).font(.system(.title, design: .rounded).weight(.semibold)).foregroundStyle(p.dim)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits the surname shown on every card")
        }
    }

    private func done() {
        editing = false
        onSurname(draft.trimmingCharacters(in: .whitespaces))
    }
}
