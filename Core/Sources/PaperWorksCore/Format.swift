import Foundation

private let MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

private func parts(_ date: CivilDate) -> (y: String, m: Int, d: Int) {
    let p = date.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    return (p[0], Int(p[1]) ?? 1, p.count > 2 ? Int(p[2]) ?? 1 : 1)
}

private func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }
private func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }

/// Nov 12, 2026
public func formatDate(_ date: CivilDate) -> String { let p = parts(date); return "\(MONTHS[p.m - 1]) \(p.d), \(p.y)" }
/// Nov 12
public func formatShort(_ date: CivilDate) -> String { let p = parts(date); return "\(MONTHS[p.m - 1]) \(p.d)" }
/// Nov 2026
public func formatMonth(_ date: CivilDate) -> String { let p = parts(date); return "\(MONTHS[p.m - 1]) \(p.y)" }

/// As precise as the date is actually known: 2013 · Sep 2024 · Sep 14, 2024.
public func formatPrecise(_ date: CivilDate, _ precision: DatePrecision) -> String {
    switch precision {
    case .year: return String(date.prefix(4))
    case .month: return formatMonth(date)
    case .day: return formatDate(date)
    }
}

/// in 47 days · 5 days late · today
public func formatRelative(_ date: CivilDate, now: CivilDate = today()) -> String {
    let days = diffDays(now, date)
    if days == 0 { return "today" }
    if days == -1 { return "1 day late" }
    if days < 0 { return days > -60 ? "\(-days) days late" : "\(jsRound(Double(-days) / 30)) months late" }
    if days == 1 { return "tomorrow" }
    if days < 45 { return "in \(days) days" }
    if days < 365 { return "in \(jsRound(Double(days) / 30.44)) months" }
    return "in \(plural(jsRound(Double(days) / 365.25), "year"))"
}

/// 13 years ago · in 3 years
public func formatAgo(_ date: CivilDate, now: CivilDate = today()) -> String {
    let days = diffDays(date, now)
    if days < 0 { return formatRelative(date, now: now) }
    if days == 0 { return "today" }
    if days < 45 { return "\(plural(days, "day")) ago" }
    if days < 365 { return "\(jsRound(Double(days) / 30.44)) months ago" }
    return "\(plural(Int((Double(days) / 365.25).rounded(.down)), "year")) ago"
}

/// 2w · 3d
public func formatSpan(_ days: Int) -> String {
    if days % 7 == 0 && days >= 7 { return "\(days / 7)w" }
    if days >= 60 { return "\(jsRound(Double(days) / 30.44))mo" }
    return "\(days)d"
}

/// 3 months · 2 years · 45 days
public func formatDuration(_ days: Int) -> String {
    if days >= 365 && days % 365 < 20 { return plural(jsRound(Double(days) / 365), "year") }
    if days >= 28 { return plural(jsRound(Double(days) / 30.44), "month") }
    return plural(days, "day")
}

/// 17 days · until Mar 2029
public func formatLasts(_ start: CivilDate, _ end: CivilDate) -> String {
    let days = diffDays(start, end)
    return days < 60 ? plural(days, "day") : "until \(formatMonth(end))"
}

/// age 18 · ages 4–5 · age 16+
public func formatAges(_ ages: AgeRange) -> String {
    guard let to = ages.to else { return "age \(ages.from)+" }
    return to == ages.from ? "age \(ages.from)" : "ages \(ages.from)–\(to)"
}
