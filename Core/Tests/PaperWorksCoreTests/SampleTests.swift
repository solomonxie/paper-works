import Foundation
import Testing
@testable import PaperWorksCore

@Suite struct SampleTests {
    @Test func demoDatesResolveAgainstToday() {
        #expect(demoDate(.fixed("1991-04-12"), "2026-10-01") == "1991-04-12")
        #expect(demoDate(.days(30), "2026-10-01") == "2026-10-31")
        #expect(demoDate(.yearly(years: -2, on: "09-14"), "2026-10-01") == "2024-09-14")
    }

    @Test func demoNamesOnlyBundledPlaybooks() throws {
        let ids = Set(bundledPlaybooks.map(\.id))
        let named = DEMO_EVENTS.flatMap(\.plans) + DEMO_PERSON_PLANS.flatMap(\.plans)
        #expect(named.filter { !ids.contains($0) }.isEmpty)
    }

    @Test func demoSeedStartsEmptyWithFlags() {
        let s = demoSeed()
        #expect(s.anchors.isEmpty)
        #expect(s.settings.firstRunDone && s.settings.icloudBackup && s.settings.askedNotifications)
        #expect(s.people == [ME_PERSON])
    }
}

@Suite struct SettingsDecodingTests {
    @Test func partialJSONFallsBackToDefaults() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"leadDays":7}"#.utf8))
        var want = DEFAULT_SETTINGS
        want.leadDays = 7
        #expect(s == want)
        #expect(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)) == DEFAULT_SETTINGS)
    }

    @Test func fullRNBlob() throws {
        let json = #"""
        {"leadDays":21,"digestWeekday":2,"digestHour":8,"digestOn":false,"calendarMirror":true,"icloudBackup":true,
         "haptics":false,"lastExport":{"on":"2026-09-01","bytes":1234},"deniedBannerDismissed":true,
         "collapsed":["later"],"firstRunDone":true,"askedNotifications":true,"personId":"p2"}
        """#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(s.leadDays == 21 && s.digestWeekday == 2 && s.digestHour == 8 && !s.digestOn)
        #expect(s.calendarMirror && s.icloudBackup && !s.haptics)
        #expect(s.lastExport == LastExport(on: "2026-09-01", bytes: 1234))
        #expect(s.collapsed == ["later"] && s.firstRunDone && s.askedNotifications && s.personId == "p2")
        #expect(s.names == nil)
    }

    @Test func roundTrips() throws {
        var s = DEFAULT_SETTINGS
        s.lastExport = LastExport(on: "2026-01-01", bytes: 5)
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func backupRoundTripAndErrors() {
        let text = serializePlan(EMPTY_PLAN, "2026-09-26")
        #expect(parseBackup(text) == .ok(EMPTY_PLAN))
        #expect(parseBackup("nope") == .failure("This file isn't JSON."))
        #expect(parseBackup(#"{"format":"x"}"#) == .failure("This isn't a Paper Works backup."))
        #expect(parseBackup(#"{"format":"paper-works-backup","version":9}"#) == .failure("This backup is from a newer version of the app."))
        #expect(parseBackup(#"{"format":"life-chapters-backup","version":1,"anchors":[]}"#) == .failure("The backup is missing its playbooks."))
    }
}
