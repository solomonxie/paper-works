import Foundation
import PaperWorksCore

public enum ICloudStatus: String, Sendable {
  case available, driveOff, notEntitled, notReady
}

/// Dated daily files, `latest.json` and a `Scans/` folder in the user's own iCloud Drive › Paper Works.
/// The app only touches the file system; iOS does the syncing, under the user's account.
public enum ICloudBackup {
  // Reads may wait on a download; they must never hold up a write.
  private static let writeQueue = DispatchQueue(label: "ICloudBackup.write", qos: .utility)
  private static let readQueue = DispatchQueue(label: "ICloudBackup.read", qos: .utility)

  public static func status() async -> ICloudStatus {
    await readQueue.value { current().status }
  }

  public static func write(_ name: String, text: String) async throws {
    try await writeQueue.run {
      guard let docs = current().documents else { throw Failure.unavailable }
      try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
      let target = docs.appendingPathComponent(name)
      var coordError: NSError?
      var writeError: Error?
      NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordError) { url in
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { writeError = error }
      }
      if let error = coordError ?? writeError { throw error }
    }
  }

  /// File names, including ones not downloaded yet (listed under their real name).
  public static func list() async -> [String] {
    await readQueue.value {
      guard let docs = current().documents else { return [] }
      let entries = (try? FileManager.default.contentsOfDirectory(atPath: docs.path)) ?? []
      let names = entries.map { entry -> String in
        entry.hasPrefix(".") && entry.hasSuffix(".icloud")
          ? String(entry.dropFirst().dropLast(".icloud".count))
          : entry
      }
      return Array(Set(names)).sorted(by: >)
    }
  }

  /// A coordinated read downloads the file first if iOS evicted it.
  public static func read(_ name: String) async throws -> String {
    try await readQueue.run {
      guard let docs = current().documents else { throw Failure.unavailable }
      let url = docs.appendingPathComponent(name)
      try? FileManager.default.startDownloadingUbiquitousItem(at: url)
      var coordError: NSError?
      var text: String?
      NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
        text = try? String(contentsOf: readURL, encoding: .utf8)
      }
      guard let text else {
        throw Failure.read(coordError?.localizedDescription ?? "Couldn't read \(name)")
      }
      return text
    }
  }

  public static func delete(_ names: [String]) async {
    await writeQueue.value {
      guard let docs = current().documents else { return }
      for name in names where !name.contains("/") {
        let url = docs.appendingPathComponent(name)
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: nil) { try? FileManager.default.removeItem(at: $0) }
      }
    }
  }

  public static let latestName = "latest.json"

  /// Copies scans that are new or changed; never deletes.
  public static func syncScans(from local: URL) async throws {
    try await writeQueue.run {
      guard let docs = current().documents else { throw Failure.unavailable }
      let fm = FileManager.default
      let dest = docs.appendingPathComponent("Scans", isDirectory: true)
      try fm.createDirectory(at: dest, withIntermediateDirectories: true)
      for name in (try? fm.contentsOfDirectory(atPath: local.path)) ?? [] where !name.hasPrefix(".") {
        let src = local.appendingPathComponent(name)
        let target = dest.appendingPathComponent(name)
        if let a = try? fm.attributesOfItem(atPath: src.path), let b = try? fm.attributesOfItem(atPath: target.path),
           a[.size] as? Int == b[.size] as? Int, (b[.modificationDate] as? Date ?? .distantPast) >= (a[.modificationDate] as? Date ?? .distantPast) {
          continue
        }
        var coordError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordError) { url in
          do {
            try? fm.removeItem(at: url)
            try fm.copyItem(at: src, to: url)
          } catch { copyError = error }
        }
        if let error = coordError ?? copyError { throw error }
      }
    }
  }

  /// Newest snapshot text, waiting up to `timeout` seconds for iCloud to show and download it.
  public static func newestSnapshot(timeout: TimeInterval) async -> String? {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
      let state = await readQueue.value { current() }
      if state.status == .driveOff { return nil }
      if state.status == .available {
        let names = await list()
        let pick = names.contains(latestName) ? latestName : names.first { dailyDay($0) != nil }
        if let pick, let text = await fetch(pick, in: "", until: deadline) { return text }
      }
      if Date() >= deadline { return nil }
      try? await Task.sleep(for: .milliseconds(500))
    }
  }

  /// Brings every scan in iCloud that is missing locally into `local`.
  public static func restoreScans(to local: URL, timeout: TimeInterval) async {
    let deadline = Date().addingTimeInterval(timeout)
    let names = await readQueue.value { () -> [String] in
      guard let docs = current().documents else { return [] }
      let entries = (try? FileManager.default.contentsOfDirectory(atPath: docs.appendingPathComponent("Scans").path)) ?? []
      return entries.map { $0.hasPrefix(".") && $0.hasSuffix(".icloud") ? String($0.dropFirst().dropLast(".icloud".count)) : $0 }
    }
    for name in Set(names) where !FileManager.default.fileExists(atPath: local.appendingPathComponent(name).path) {
      guard await fetch(name, in: "Scans", until: deadline, copyTo: local.appendingPathComponent(name)) != nil else { continue }
    }
  }

  private static func fetch(_ name: String, in folder: String, until deadline: Date, copyTo: URL? = nil) async -> String? {
    guard let docs = await readQueue.value({ current().documents }) else { return nil }
    let url = folder.isEmpty ? docs.appendingPathComponent(name) : docs.appendingPathComponent(folder).appendingPathComponent(name)
    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    while !FileManager.default.fileExists(atPath: url.path) {
      if Date() >= deadline { return nil }
      try? await Task.sleep(for: .milliseconds(300))
    }
    return await readQueue.value {
      var coordError: NSError?
      var result: String?
      NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
        if let copyTo {
          if (try? FileManager.default.copyItem(at: readURL, to: copyTo)) != nil { result = "" }
        } else {
          result = try? String(contentsOf: readURL, encoding: .utf8)
        }
      }
      return result
    }
  }

  private static func current() -> (status: ICloudStatus, documents: URL?) {
    if let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
      return (.available, container.appendingPathComponent("Documents"))
    }
    if FileManager.default.ubiquityIdentityToken == nil { return (.driveOff, nil) }
    return (.notReady, nil)
  }

  public enum Failure: LocalizedError {
    case unavailable
    case read(String)

    public var errorDescription: String? {
      switch self {
      case .unavailable: "iCloud Drive is not available"
      case .read(let message): message
      }
    }
  }
}
