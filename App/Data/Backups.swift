import Foundation
import PaperWorksCore

/// Backup files and iCloud, redirected to memory while demo data is on screen (like src/platform).
@MainActor
enum BackupStorage {
    static var demoMode = false
    private static var memBackups: [String: String] = [:]
    private static var memICloud: [String: String] = [:]

    static func writeBackup(_ name: String, _ text: String) async throws {
        if demoMode { memBackups[name] = text } else { try await Files.writeBackup(name, text: text) }
    }
    static func appendBackup(_ name: String, _ text: String) async throws {
        if demoMode { memBackups[name, default: ""] += text } else { try await Files.appendBackup(name, text: text) }
    }
    static func listBackups() async -> [String] {
        demoMode ? Array(memBackups.keys) : await Files.listBackups()
    }
    static func readBackup(_ name: String) async throws -> String {
        if demoMode {
            guard let t = memBackups[name] else { throw DatabaseError.sql("\(name) not found") }
            return t
        }
        return try await Files.readBackup(name)
    }
    static func deleteBackups(_ names: [String]) async {
        if demoMode { names.forEach { memBackups[$0] = nil } } else { await Files.deleteBackups(names) }
    }
    static func icloudStatus() async -> ICloudStatus {
        demoMode ? .available : await ICloudBackup.status()
    }
    static func icloudWrite(_ name: String, _ text: String) async throws {
        if demoMode { memICloud[name] = text } else { try await ICloudBackup.write(name, text: text) }
    }
    static func icloudList() async -> [String] {
        demoMode ? Array(memICloud.keys) : await ICloudBackup.list()
    }
    static func icloudRead(_ name: String) async throws -> String {
        if demoMode {
            guard let t = memICloud[name] else { throw DatabaseError.sql("\(name) not found") }
            return t
        }
        return try await ICloudBackup.read(name)
    }

    /// Whole-snapshot write: latest + dated file + scans. Demo data stays in memory.
    static func icloudWriteSnapshot(_ text: String, day: CivilDate) async throws {
        if demoMode {
            memICloud[ICloudBackup.latestName] = text
            memICloud[dailyName(day)] = text
            dailiesToPrune(Array(memICloud.keys), day).forEach { memICloud[$0] = nil }
            return
        }
        try await ICloudBackup.write(ICloudBackup.latestName, text: text)
        try await ICloudBackup.write(dailyName(day), text: text)
        try await ICloudBackup.syncScans(from: Files.scansURL)
        await ICloudBackup.delete(dailiesToPrune(await ICloudBackup.list(), day))
    }
}
