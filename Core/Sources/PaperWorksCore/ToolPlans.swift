import Foundation

public enum PlanKind: String, Codable, Sendable, CaseIterable, Identifiable { case paperwork, babyNames; public var id: String { rawValue } }

/// A plan that isn't a scheduled playbook: a tool the person keeps on their board.
public struct ToolPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: PlanKind
    public var personId: String?
    public var anchorId: String?
    public var addedOn: CivilDate
    public var title: String?
    /// Baby-names state owned by this plan.
    public var names: NameState?
    public init(id: String, kind: PlanKind, personId: String? = nil, anchorId: String? = nil, addedOn: CivilDate,
                title: String? = nil, names: NameState? = nil) {
        self.id = id; self.kind = kind; self.personId = personId; self.anchorId = anchorId; self.addedOn = addedOn
        self.title = title; self.names = names
    }
}

public func eventLabel(_ a: Anchor) -> String { "\(a.label) \(formatMonth(a.date))" }

/// "Baby names", "Baby names · Baby due Jun 2027", or "Baby names (2)" for later plans without an event.
public func toolPlanTitle(_ tp: ToolPlan, in plans: [ToolPlan], anchors: [Anchor]) -> String {
    if let t = tp.title, !t.isEmpty { return t }
    let base = toolPlanKind(tp.kind)?.title ?? "Plan"
    if let a = anchors.first(where: { $0.id == tp.anchorId }) { return "\(base) · \(eventLabel(a))" }
    let bare = plans.filter { q in q.kind == tp.kind && !anchors.contains { $0.id == q.anchorId } }
    guard let i = bare.firstIndex(where: { $0.id == tp.id }), i > 0 else { return base }
    return "\(base) (\(i + 1))"
}

/// Moves the legacy global names state into the first baby-names plan (creating one for `owner`), then clears it.
public func migrateNames(_ s: Settings, owner: String, newId: () -> String, today: CivilDate) -> Settings {
    guard let n = s.names else { return s }
    var out = s
    out.names = nil
    guard !n.history.isEmpty || !n.liked.isEmpty || !n.passed.isEmpty || !n.custom.isEmpty else { return out }
    if let i = out.toolPlans.firstIndex(where: { $0.kind == .babyNames }) {
        if out.toolPlans[i].names == nil { out.toolPlans[i].names = n }
    } else {
        out.toolPlans.append(ToolPlan(id: newId(), kind: .babyNames, personId: owner, addedOn: today, names: n))
    }
    return out
}

public struct ToolPlanKind: Equatable, Sendable {
    public var kind: PlanKind
    public var title: String
    public var summary: String
    public var symbol: String
    /// Anchor kinds that suggest this plan.
    public var suggestedBy: [String]
}

public let TOOL_PLAN_KINDS: [ToolPlanKind] = [
    ToolPlanKind(kind: .babyNames, title: "Baby names", summary: "Swipe through names, keep the ones you like.",
                 symbol: "heart.text.square.fill", suggestedBy: ["baby-due", "child-born"]),
]

public func toolPlanKind(_ kind: PlanKind) -> ToolPlanKind? { TOOL_PLAN_KINDS.first { $0.kind == kind } }

public func toolPlanKinds(suggestedBy anchorKind: String) -> [ToolPlanKind] {
    TOOL_PLAN_KINDS.filter { $0.suggestedBy.contains(anchorKind) }
}
