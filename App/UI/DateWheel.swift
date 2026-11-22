import SwiftUI
import PaperWorksCore

/// In-place date picker; columns follow precision (day: month·day·year, month: month·year, year: year).
struct DateWheel: View {
    @Binding var date: CivilDate
    var precision: DatePrecision = .day
    var years: ClosedRange<Int> = 1900...2100

    var body: some View {
        switch precision {
        case .day:
            DatePicker("", selection: dayBinding, in: dayRange, displayedComponents: .date)
                .datePickerStyle(.wheel).labelsHidden()
        case .month, .year:
            HStack(spacing: 0) {
                if precision == .month {
                    Picker("Month", selection: monthBinding) {
                        ForEach(1...12, id: \.self) { Text(Self.monthNames[$0 - 1]).tag($0) }
                    }
                    .pickerStyle(.wheel)
                }
                Picker("Year", selection: yearBinding) {
                    ForEach(Array(years), id: \.self) { Text(String($0)).tag($0) }
                }
                .pickerStyle(.wheel)
            }
            .frame(height: 216)
        }
    }

    private static let monthNames = Calendar(identifier: .gregorian).monthSymbols

    private var parts: (y: Int, m: Int, d: Int) {
        let f = date.split(separator: "-").compactMap { Int($0) }
        return (f[safe: 0] ?? 2000, f[safe: 1] ?? 1, f[safe: 2] ?? 1)
    }

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private var dayRange: ClosedRange<Date> {
        Self.calendar.date(from: DateComponents(year: years.lowerBound, month: 1, day: 1))!...Self.calendar.date(
            from: DateComponents(year: years.upperBound, month: 12, day: 31))!
    }

    private var dayBinding: Binding<Date> {
        Binding(
            get: { Self.calendar.date(from: DateComponents(year: parts.y, month: parts.m, day: parts.d)) ?? Date() },
            set: {
                let c = Self.calendar.dateComponents([.year, .month, .day], from: $0)
                date = Self.format(c.year!, c.month!, c.day!)
            })
    }

    private var monthBinding: Binding<Int> {
        Binding(get: { parts.m }, set: { date = Self.clamped(parts.y, $0, parts.d) })
    }

    private var yearBinding: Binding<Int> {
        Binding(get: { parts.y }, set: { date = Self.clamped($0, parts.m, parts.d) })
    }

    private static func format(_ y: Int, _ m: Int, _ d: Int) -> CivilDate {
        String(format: "%04d-%02d-%02d", y, m, d)
    }

    private static func clamped(_ y: Int, _ m: Int, _ d: Int) -> CivilDate {
        let last = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: y, month: m))!)!.upperBound - 1
        return format(y, m, min(d, last))
    }
}
