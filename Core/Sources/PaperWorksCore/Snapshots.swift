import Foundation

/// Files kept per calendar day: the day's copy, plus a tagged one or older per-change ones.
public let PER_DAY = 5
/// Days of copies kept, today included. The change log is never pruned.
public let KEEP_DAYS = 30

private func pad(_ n: Int, _ w: Int = 2) -> String {
    let s = String(n)
    return String(repeating: "0", count: max(0, w - s.count)) + s
}

private func dayOf(_ at: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: at)
    return "\(pad(c.year!, 4))-\(pad(c.month!))-\(pad(c.day!))"
}

/// One file per day, `2026-09-26.json` in local time; a tag keeps a one-off apart.
public func snapshotName(_ at: Date, _ tag: String? = nil) -> String {
    "\(dayOf(at))\(tag.map { "-\($0)" } ?? "").json"
}

private let snapshotPattern = try! NSRegularExpression(
    pattern: #"^\d{4}-\d{2}-\d{2}(?:T(\d{2})(?:-(\d{2})-\d{2}-\d{3})?)?(?:-([a-z-]+))?\.json$"#)

private func snapshotMatch(_ name: String) -> NSTextCheckingResult? {
    snapshotPattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name))
}

private func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String? {
    let r = m.range(at: i)
    return r.location == NSNotFound ? nil : Range(r, in: s).map { String(s[$0]) }
}

public func isSnapshot(_ name: String) -> Bool { snapshotMatch(name) != nil }

public func snapshotDay(_ name: String) -> CivilDate { String(name.prefix(10)) }

/// "latest", "before restore", or a time for an older hourly or per-change file.
public func snapshotTime(_ name: String) -> String {
    guard let m = snapshotMatch(name) else { return "" }
    let hour = group(m, 1, in: name), minute = group(m, 2, in: name)
    let tag = group(m, 3, in: name)?.replacingOccurrences(of: "-", with: " ")
    if let hour { return "\(hour):\(minute ?? "00")\(tag.map { " \($0)" } ?? "")" }
    return tag ?? "latest"
}

/// Which snapshots to delete: older than the window, and past each day's newest few. Non-snapshots untouched.
public func snapshotsToPrune(_ names: [String], _ today: CivilDate, perDay: Int = PER_DAY, days: Int = KEEP_DAYS) -> [String] {
    let oldest = addDays(today, -(days - 1))
    var byDay: [String: [String]] = [:]
    var out: [String] = []
    for name in names.filter(isSnapshot) {
        let day = snapshotDay(name)
        if day < oldest { out.append(name) } else { byDay[day, default: []].append(name) }
    }
    for list in byDay.values { out.append(contentsOf: list.sorted(by: >).dropFirst(perDay)) }
    return out.sorted()
}

public struct SnapshotDay: Equatable, Sendable {
    public var day: CivilDate
    public var names: [String]
}

/// Newest first, grouped by day.
public func groupSnapshots(_ names: [String]) -> [SnapshotDay] {
    var order: [String] = []
    var byDay: [String: [String]] = [:]
    for n in names.filter(isSnapshot).sorted(by: >) {
        let d = snapshotDay(n)
        if byDay[d] == nil { order.append(d) }
        byDay[d, default: []].append(n)
    }
    return order.map { SnapshotDay(day: $0, names: byDay[$0]!) }
}

/// The one iCloud file for a day, replaced on every change that day.
public func dailyName(_ day: CivilDate) -> String { "paper-works-\(day).json" }

public func dailyDay(_ name: String) -> CivilDate? {
    guard name.hasPrefix("paper-works-"), name.hasSuffix(".json") else { return nil }
    let day = String(name.dropFirst(12).dropLast(5))
    let parts = day.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts.map(\.count) == [4, 2, 2], parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return nil }
    return day
}

/// Append-only, one file a year, plain text readable in Files.
public func changeLogName(_ at: Date) -> String { "changes-\(Calendar.current.component(.year, from: at)).log" }

/// `2026-09-27 14:03:22\tMe\tAva born moved · 3 steps rescheduled`
public func changeLine(_ at: Date, _ who: String, _ what: String) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute, .second], from: at)
    let flat = what.replacingOccurrences(of: "[\\t\\n]+", with: " ", options: .regularExpression)
    return "\(dayOf(at)) \(pad(c.hour!)):\(pad(c.minute!)):\(pad(c.second!))\t\(who)\t\(flat)\n"
}
