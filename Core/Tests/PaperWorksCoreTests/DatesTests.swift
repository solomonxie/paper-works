import Testing
@testable import PaperWorksCore

struct DatesTests {
    @Test func roundTripsThroughDayNumbers() {
        for date in ["1991-04-12", "2024-02-29", "2027-01-01"] { #expect(fromDayNumber(toDayNumber(date)) == date) }
    }
    @Test func crossesMonthYearAndLeapBoundaries() {
        #expect(addDays("2026-12-31", 1) == "2027-01-01")
        #expect(addDays("2024-02-28", 1) == "2024-02-29")
        #expect(addDays("2025-02-28", 1) == "2025-03-01")
        #expect(addDays("2027-01-01", -1) == "2026-12-31")
    }
    @Test func diffsSigned() {
        #expect(diffDays("2026-09-26", "2026-10-01") == 5)
        #expect(diffDays("2026-10-01", "2026-09-26") == -5)
    }
    @Test func resolvesFuzzyAnchors() {
        #expect(resolve("2013-01-01", .year) == "2013-07-01")
        #expect(resolve("2013-03-01", .month) == "2013-03-15")
        #expect(resolve("2013-03-09", .day) == "2013-03-09")
    }
    @Test func countsWholeYears() {
        #expect(yearsBetween("1991-04-12", "2026-09-26") == 35)
        #expect(yearsBetween("1991-04-12", "1992-04-11") == 0)
        #expect(maxDate("2026-09-26", "2026-10-01", "2025-01-01") == "2026-10-01")
    }
}
