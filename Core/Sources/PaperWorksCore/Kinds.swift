import Foundation

public struct AnchorKind: Codable, Equatable, Identifiable, Sendable {
    public struct Purpose: Codable, Equatable, Sendable {
        public var id: String
        public var label: String
    }
    public enum From: String, Codable, Sendable { case `self`, born, child }
    public struct AlsoOpens: Codable, Equatable, Sendable {
        public var kind: String
        public var families: [String]?
        public var from: From
    }
    public var id: String
    public var label: String
    public var group: String
    public var chapter: String
    public var withDetail: String?
    public var moment: Bool?
    public var alsoOpens: AlsoOpens?
    public var ends: String?
    public var purposes: [Purpose]?
}

private struct KindsFile: Decodable {
    let kinds: [AnchorKind]
    let tripPurposes: [AnchorKind.Purpose]
}

private let kindsFile: KindsFile = {
    do { return try JSONDecoder().decode(KindsFile.self, from: bundledResource("kinds")) }
    catch { fatalError("kinds.json: \(error)") }
}()

public let ANCHOR_KINDS: [AnchorKind] = kindsFile.kinds
public let TRIP_PURPOSES: [AnchorKind.Purpose] = kindsFile.tripPurposes

public func kindById(_ id: String) -> AnchorKind? { ANCHOR_KINDS.first { $0.id == id } }

/// Whether an event of `kind` opens this plan, and what the plan counts from.
public func opens(_ kind: String, _ pb: Playbook) -> AnchorKind.From? { opens(kind, anchorKind: pb.anchorKind, family: pb.family) }

public func opens(_ kind: String, anchorKind: String, family: String? = nil) -> AnchorKind.From? {
    if anchorKind == kind { return .`self` }
    guard let also = kindById(kind)?.alsoOpens, anchorKind == also.kind else { return nil }
    guard let families = also.families else { return also.from }
    if let family, families.contains(family) { return also.from }
    return nil
}

public func kindLabel(_ id: String) -> String { kindById(id)?.label ?? id }

/// "Migrated to Canada", "Born · Xi'an", or just the label.
public func anchorTitle(_ kind: String, _ label: String, _ detail: String? = nil) -> String {
    guard let detail, !detail.isEmpty else { return label }
    if let k = kindById(kind), let with = k.withDetail, label == k.label {
        return with.replacingOccurrences(of: "{}", with: detail, options: [], range: with.range(of: "{}"))
    }
    return "\(label) · \(detail)"
}
