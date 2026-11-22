import Foundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension DispatchQueue {
  func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      self.async(execute: { continuation.resume(with: Result { try body() }) })
    }
  }

  func value<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
      self.async(execute: { continuation.resume(returning: body()) })
    }
  }
}

public enum ScanSource: String, Sendable {
  case camera, photos, files
}

/// Text out through the share sheet, files in through the pickers, and scans and
/// backups kept in the app's own folders, visible in Files.
@MainActor
public final class Files: NSObject, UIDocumentPickerDelegate, UIImagePickerControllerDelegate,
  UINavigationControllerDelegate, PHPickerViewControllerDelegate
{
  public static let shared = Files()

  public enum Folder: Sendable {
    case scans, backups
  }

  private var pending: CheckedContinuation<String?, Never>?
  private var pendingIsScan = false

  private static let backupQueue = DispatchQueue(label: "Files.backups", qos: .utility)

  private nonisolated static var documents: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  public nonisolated static var scansURL: URL { folder("Scans") }
  private nonisolated static var backupsURL: URL { folder("Backups") }

  private nonisolated static func folder(_ name: String) -> URL {
    let url = documents.appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private static func top() -> UIViewController? {
    var vc = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController
    while let next = vc?.presentedViewController { vc = next }
    return vc
  }

  // MARK: text

  public nonisolated static func writeTemp(_ name: String, text: String) throws -> String {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try text.write(to: url, atomically: true, encoding: .utf8)
    return url.path
  }

  public nonisolated static func readText(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
  }

  /// Returns whether the share sheet completed; false when there is no screen to show it on.
  public static func share(_ path: String) async -> Bool {
    guard let host = top() else { return false }
    return await withCheckedContinuation { continuation in
      let sheet = UIActivityViewController(activityItems: [URL(fileURLWithPath: path)], applicationActivities: nil)
      sheet.popoverPresentationController?.sourceView = host.view
      sheet.completionWithItemsHandler = { _, completed, _, _ in continuation.resume(returning: completed) }
      host.present(sheet, animated: true)
    }
  }

  // MARK: pickers

  /// Returns the picked file's local copy path, or nil on cancel. `kinds` are UTI strings.
  public func pickFile(_ kinds: [String]) async -> String? {
    await withCheckedContinuation { continuation in
      begin(continuation, scan: false)
      presentDocumentPicker(kinds.compactMap { UTType($0) })
    }
  }

  /// Returns the stored scan's file name, or nil on cancel.
  public func addScan(_ source: ScanSource) async -> String? {
    await withCheckedContinuation { continuation in
      begin(continuation, scan: true)
      switch source {
      case .camera:
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
          finish(nil)
          return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        present(picker)
      case .photos:
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker)
      case .files:
        presentDocumentPicker([.image, .pdf])
      }
    }
  }

  private func begin(_ continuation: CheckedContinuation<String?, Never>, scan: Bool) {
    finish(nil)
    pending = continuation
    pendingIsScan = scan
  }

  private func finish(_ value: String?) {
    let continuation = pending
    pending = nil
    continuation?.resume(returning: value)
  }

  private func presentDocumentPicker(_ types: [UTType]) {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
    picker.delegate = self
    present(picker)
  }

  private func present(_ controller: UIViewController) {
    guard let host = Files.top() else {
      finish(nil)
      return
    }
    host.present(controller, animated: true)
  }

  private nonisolated static func storeScan(_ data: Data, ext: String) -> String? {
    let name = "\(UUID().uuidString).\(ext)"
    guard (try? data.write(to: scansURL.appendingPathComponent(name), options: .atomic)) != nil else { return nil }
    return name
  }

  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      finish(nil)
      return
    }
    if pendingIsScan {
      let data = try? Data(contentsOf: url)
      finish(data.flatMap { Files.storeScan($0, ext: url.pathExtension.lowercased()) })
    } else {
      finish(url.path)
    }
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }

  public func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    picker.dismiss(animated: true)
    let image = info[.originalImage] as? UIImage
    finish(image?.jpegData(compressionQuality: 0.8).flatMap { Files.storeScan($0, ext: "jpg") })
  }

  public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    finish(nil)
  }

  public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
      finish(nil)
      return
    }
    provider.loadObject(ofClass: UIImage.self) { object, _ in
      let data = (object as? UIImage)?.jpegData(compressionQuality: 0.8)
      Task { @MainActor in
        self.finish(data.flatMap { Files.storeScan($0, ext: "jpg") })
      }
    }
  }

  // MARK: local backups (Documents/Backups)

  public nonisolated static func writeBackup(_ name: String, text: String) async throws {
    try await backupQueue.run {
      try text.write(to: backupsURL.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
  }

  /// Adds to the end of a file, creating it first: the change log is never rewritten.
  public nonisolated static func appendBackup(_ name: String, text: String) async throws {
    try await backupQueue.run {
      let url = backupsURL.appendingPathComponent(name)
      let data = Data(text.utf8)
      if FileManager.default.fileExists(atPath: url.path) {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
      } else {
        try data.write(to: url, options: .atomic)
      }
    }
  }

  public nonisolated static func listBackups() async -> [String] {
    await backupQueue.value {
      (try? FileManager.default.contentsOfDirectory(atPath: backupsURL.path)) ?? []
    }
  }

  public nonisolated static func readBackup(_ name: String) async throws -> String {
    try await backupQueue.run {
      try String(contentsOf: backupsURL.appendingPathComponent(name), encoding: .utf8)
    }
  }

  /// Names containing "/" are ignored, so a backup can't reach outside its folder.
  public nonisolated static func deleteBackups(_ names: [String]) async {
    await backupQueue.value {
      for name in names where !name.contains("/") {
        try? FileManager.default.removeItem(at: backupsURL.appendingPathComponent(name))
      }
    }
  }

  // MARK: scans

  public nonisolated static func scanPath(_ name: String) -> String? {
    let url = scansURL.appendingPathComponent(name)
    return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
  }

  public nonisolated static func deleteScan(_ name: String) {
    try? FileManager.default.removeItem(at: scansURL.appendingPathComponent(name))
  }

  /// Opens the Files app at one of this app's folders.
  public static func openFolder(_ folder: Folder) async -> Bool {
    let path = (folder == .backups ? backupsURL : scansURL).path
    guard let url = URL(string: "shareddocuments://\(path)") else { return false }
    return await UIApplication.shared.open(url)
  }
}
