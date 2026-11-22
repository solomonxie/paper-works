import Foundation

public enum Validation: Equatable, Sendable {
    case ok(Playbook)
    case failure(String)

    public var isOk: Bool { if case .ok = self { return true }; return false }
    public var error: String? { if case .failure(let e) = self { return e }; return nil }
    public var playbook: Playbook? { if case .ok(let p) = self { return p }; return nil }
}

private typealias Obj = [String: Any]

private func isCivil(_ s: String) -> Bool {
    s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
}

private func strings(_ v: Any) -> Bool { (v as? [Any])?.allSatisfy { $0 is String } ?? false }

private func int(_ v: Any) -> Int? {
    guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    let d = n.doubleValue
    return d == d.rounded() && abs(d) < 1e15 ? Int(d) : nil
}

private func ageRange(_ v: Any) -> Bool {
    guard let o = v as? Obj, let from = int(o["from"] as Any), from >= 0 else { return false }
    guard let to = o["to"] else { return true }
    guard let t = int(to) else { return false }
    return t >= from
}

private func nonEmpty(_ v: Any?) -> String? {
    guard let s = v as? String, !s.isEmpty else { return nil }
    return s
}

/// Everything an imported file must satisfy before it may produce a date. Errors
/// name the step by its title, since that's what the user can find.
/// `input` is parsed JSON (`JSONSerialization`).
public func validatePlaybook(_ input: Any?) -> Validation {
    func fail(_ e: String) -> Validation { .failure(e) }

    guard let input = input as? Obj else { return fail("This file is not a playbook.") }
    guard nonEmpty(input["id"]) != nil else { return fail("The playbook has no id.") }
    guard let title = nonEmpty(input["title"]) else { return fail("The playbook has no title.") }
    guard nonEmpty(input["anchorKind"]) != nil else {
        return fail("\"\(title)\" doesn't say which date it hangs off (anchorKind).")
    }
    guard let reviewedAt = input["reviewedAt"] as? String, isCivil(reviewedAt) else {
        return fail("\"\(title)\" has no review date (reviewedAt, YYYY-MM-DD).")
    }
    guard let steps = input["steps"] as? [Any], !steps.isEmpty else { return fail("\"\(title)\" has no steps.") }
    if let ages = input["ages"], !ageRange(ages) { return fail("\"\(title)\" has a malformed age range.") }
    if let c = input["conditions"], !strings(c) { return fail("\"\(title)\" has a malformed conditions list.") }

    var seen = Set<String>()
    var normalized: [Obj] = []
    for (i, rawAny) in steps.enumerated() {
        guard var raw = rawAny as? Obj else { return fail("Step \(i + 1) is not a step.") }
        let name = nonEmpty(raw["title"]) ?? "#\(i + 1)"
        guard let sid = nonEmpty(raw["id"]) else { return fail("Step \"\(name)\" has no id.") }
        if seen.contains(sid) { return fail("Two steps share the id \"\(sid)\".") }
        seen.insert(sid)
        if nonEmpty(raw["title"]) == nil { return fail("Step \"\(sid)\" has no title.") }
        if raw["offsetDays"].flatMap(int) == nil { return fail("Step \"\(name)\" has no whole-day offset.") }
        guard let dur = raw["durationDays"].flatMap(int), dur >= 0 else {
            return fail("Step \"\(name)\" needs a duration of zero days or more.")
        }
        if let v = raw["validForDays"], (int(v) ?? 0) <= 0 {
            return fail("Step \"\(name)\" has a validity window that isn't a positive number of days.")
        }
        if let a = raw["ages"], !ageRange(a) { return fail("Step \"\(name)\" has a malformed age range.") }
        for key in ["dependsOn", "documents", "prepare", "conditions"] {
            if let v = raw[key], !strings(v) { return fail("Step \"\(name)\" has a malformed \(key) list.") }
        }
        if let v = raw["endOffsetDays"], int(v) == nil {
            return fail("Step \"\(name)\" has an end offset that isn't whole days.")
        }
        if let v = raw["purposes"], !strings(v) { return fail("Step \"\(name)\" has a malformed purposes list.") }
        if let v = raw["howTo"], !(v is String) { return fail("Step \"\(name)\" has a malformed how-to.") }
        for key in ["dependsOn", "documents", "prepare"] where raw[key] == nil { raw[key] = [String]() }
        normalized.append(raw)
    }

    var full = input
    full["steps"] = normalized
    guard let data = try? JSONSerialization.data(withJSONObject: full),
          let playbook = try? JSONDecoder().decode(Playbook.self, from: data) else {
        return fail("This file is not a playbook.")
    }

    func titleOf(_ id: String) -> String { playbook.steps.first { $0.id == id }?.title ?? id }

    do {
        _ = try topoSort(playbook.steps)
    } catch let e as PlaybookCycleError {
        let last = e.stepIds[e.stepIds.count - 1]
        let loop = Array(e.stepIds[(e.stepIds.firstIndex(of: last) ?? 0)...])
        let (a, b) = (titleOf(loop[0]), titleOf(loop[1]))
        return fail(loop.count <= 3
            ? "Step \"\(a)\" depends on \"\(b)\", which depends back on it."
            : "Steps depend on each other in a loop: \(loop.map(titleOf).joined(separator: " → ")).")
    } catch let e as MissingDependencyError {
        return fail("Step \"\(titleOf(e.stepId))\" depends on \"\(e.missingId)\", which isn't in this playbook.")
    } catch {
        return fail("\(error)")
    }
    return .ok(playbook)
}

/// Whole years since the playbook was last checked against the real rules.
public func reviewAgeYears(_ reviewedAt: CivilDate, _ now: CivilDate) -> Int {
    Int((Double(diffDays(reviewedAt, now)) / 365.2425).rounded(.down))
}

public let STALE_AFTER_YEARS = 2

public func isStale(_ playbook: Playbook, _ now: CivilDate) -> Bool {
    reviewAgeYears(playbook.reviewedAt, now) >= STALE_AFTER_YEARS
}
