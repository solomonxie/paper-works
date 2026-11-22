import Foundation

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private let epoch = utc.date(from: DateComponents(year: 1970, month: 1, day: 1))!

private func parts(_ date: CivilDate) -> (Int, Int, Int) {
    let p = date.split(separator: "-").map { Int($0) ?? 1 }
    return (p[0], p.count > 1 ? p[1] : 1, p.count > 2 ? p[2] : 1)
}

public func toDayNumber(_ date: CivilDate) -> Int {
    let (y, m, d) = parts(date)
    let day = utc.date(from: DateComponents(year: y, month: m, day: d))!
    return utc.dateComponents([.day], from: epoch, to: day).day!
}

public func fromDayNumber(_ days: Int) -> CivilDate {
    let c = utc.dateComponents([.year, .month, .day], from: utc.date(byAdding: .day, value: days, to: epoch)!)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}

public func addDays(_ date: CivilDate, _ days: Int) -> CivilDate { fromDayNumber(toDayNumber(date) + days) }

/// Signed day count from `from` to `to`.
public func diffDays(_ from: CivilDate, _ to: CivilDate) -> Int { toDayNumber(to) - toDayNumber(from) }

public func minDate(_ dates: CivilDate...) -> CivilDate { dates.min()! }
public func maxDate(_ dates: CivilDate...) -> CivilDate { dates.max()! }

/// Today as a civil date in the device's own zone.
public func today(_ now: Date = Date(), calendar: Calendar = .current) -> CivilDate {
    let c = calendar.dateComponents([.year, .month, .day], from: now)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}

/// "Graduated in 2013" schedules from mid-2013 rather than January 1st.
public func resolve(_ date: CivilDate, _ precision: DatePrecision) -> CivilDate {
    let (y, m, _) = parts(date)
    switch precision {
    case .year: return String(format: "%04d-07-01", y)
    case .month: return String(format: "%04d-%02d-15", y, m)
    case .day: return date
    }
}

public func yearsBetween(_ from: CivilDate, _ to: CivilDate) -> Int {
    Int((Double(diffDays(from, to)) / 365.2425).rounded(.down))
}
