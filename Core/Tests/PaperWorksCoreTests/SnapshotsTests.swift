import Foundation
import Testing
@testable import PaperWorksCore

private let TODAY = "2026-09-26"
private func at(_ day: String, _ i: Int) -> String { "\(day)T10-00-\(i < 10 ? "0" : "")\(i)-000.json" }
private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi, second: s))!
}

@Suite struct SnapshotsTests {
    @Test func oneFileADay() {
        #expect(snapshotName(local(2026, 9, 26, 21, 5, 3)) == "2026-09-26.json")
        #expect(snapshotName(local(2026, 9, 26, 9), "before-restore") == "2026-09-26-before-restore.json")
        #expect(snapshotTime("2026-09-26.json") == "latest")
        #expect(snapshotTime("2026-09-26-before-restore.json") == "before restore")
    }

    @Test func readsOlderNames() {
        #expect(snapshotTime("2026-09-26T21.json") == "21:00")
        #expect(snapshotTime("2026-09-26T21-05-33-120.json") == "21:05")
        #expect(snapshotsToPrune(["2026-09-26T21-05-33-120.json"], TODAY) == [])
    }

    @Test func keepsNewestFewOfADay() {
        let day = (0..<8).map { at(TODAY, $0) }
        #expect(snapshotsToPrune(day, TODAY) == Array(day.prefix(3)))
    }

    @Test func keeps30Days() {
        let names = ["2026-08-28.json", "2026-08-27.json", "2026-01-01.json", "\(TODAY).json"]
        #expect(snapshotsToPrune(names, TODAY) == ["2026-01-01.json", "2026-08-27.json"])
    }

    @Test func neverTouchesNonSnapshots() {
        #expect(snapshotsToPrune(["notes.txt", "paper-works-2020-01-01.json", "changes-2020.log"], TODAY) == [])
    }

    @Test func changeLineFlattensNewlines() {
        let d = local(2026, 9, 27, 14, 3, 22)
        #expect(changeLogName(d) == "changes-2026.log")
        #expect(changeLine(d, "Me", "Ava born moved\n3 steps") == "2026-09-27 14:03:22\tMe\tAva born moved 3 steps\n")
    }

    @Test func groupsNewestFirst() {
        let g = groupSnapshots([at("2026-09-25", 1), at(TODAY, 1), at(TODAY, 2), "x.json"])
        #expect(g.map(\.day) == [TODAY, "2026-09-25"])
        #expect(g[0].names == [at(TODAY, 2), at(TODAY, 1)])
    }

    @Test func oneICloudNamePerDay() {
        #expect(dailyName(TODAY) == "paper-works-2026-09-26.json")
        #expect(dailyDay(dailyName(TODAY)) == TODAY)
        #expect(dailyDay("other.json") == nil)
    }
}
