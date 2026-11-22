import Foundation
import Testing
@testable import PaperWorksCore

@Suite struct FullSnapshotTests {
    private func sample() -> Stored {
        var s = Stored(plan: EMPTY_PLAN)
        s.settings.leadDays = 30
        s.settings.icloudBackup = false
        var names = NameState()
        names.liked = ["Ava"]
        names.surname = "Xie"
        s.settings.names = names
        s.moves = ["a:b": Move(from: "2026-01-01", to: "2026-02-01", on: "2026-01-05", cause: "Edit")]
        return s
    }

    @Test func roundTripsSettingsAndMoves() {
        let s = sample()
        let text = serializeStored(s, "2026-09-26")
        guard case .ok(let plan, let settings, let moves) = parseSnapshot(text) else { Issue.record("no parse"); return }
        #expect(plan == s.plan)
        #expect(settings == s.settings)
        #expect(moves == s.moves)
        #expect(parseBackup(text) == .ok(s.plan))
    }

    @Test func versionTwoFileHasNoSettings() {
        let text = serializePlan(EMPTY_PLAN, "2026-09-26")
            .replacingOccurrences(of: "\"version\" : \(BACKUP_VERSION)", with: "\"version\" : 2")
        guard case .ok(_, let settings, let moves) = parseSnapshot(text) else { Issue.record("no parse"); return }
        #expect(settings == nil && moves == nil)
    }

    @Test func newerVersionRefused() {
        let text = serializePlan(EMPTY_PLAN, "2026-09-26")
            .replacingOccurrences(of: "\"version\" : \(BACKUP_VERSION)", with: "\"version\" : \(BACKUP_VERSION + 1)")
        #expect(parseSnapshot(text) == .failure("This backup is from a newer version of the app."))
    }

    @Test func icloudOnByDefault() {
        #expect(DEFAULT_SETTINGS.icloudBackup)
    }
}

@Suite struct DailiesPruneTests {
    @Test func prunesOldDatedFilesOnly() {
        let names = ["latest.json", dailyName("2026-08-01"), dailyName("2026-09-26"), "Scans"]
        #expect(dailiesToPrune(names, "2026-09-26") == [dailyName("2026-08-01")])
    }
}
