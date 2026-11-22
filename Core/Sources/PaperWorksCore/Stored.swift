import Foundation

public struct LastExport: Codable, Equatable, Sendable {
    public var on: CivilDate
    public var bytes: Int
    public init(on: CivilDate, bytes: Int) { self.on = on; self.bytes = bytes }
}

public struct Settings: Codable, Equatable, Sendable {
    public var leadDays: Int
    /// 1 = Sunday, per iOS.
    public var digestWeekday: Int
    public var digestHour: Int
    public var digestOn: Bool
    public var calendarMirror: Bool
    public var icloudBackup: Bool
    public var haptics: Bool
    public var lastExport: LastExport?
    public var deniedBannerDismissed: Bool
    public var collapsed: [String]
    public var firstRunDone: Bool
    public var askedNotifications: Bool
    /// Whose board is showing.
    public var personId: String
    public var names: NameState?
    public var toolPlans: [ToolPlan]

    public init(leadDays: Int = 14, digestWeekday: Int = 1, digestHour: Int = 9, digestOn: Bool = true,
                calendarMirror: Bool = false, icloudBackup: Bool = true, haptics: Bool = true,
                lastExport: LastExport? = nil, deniedBannerDismissed: Bool = false,
                collapsed: [String] = ["year", "later"], firstRunDone: Bool = false,
                askedNotifications: Bool = false, personId: String = ME, names: NameState? = nil, toolPlans: [ToolPlan] = []) {
        self.leadDays = leadDays; self.digestWeekday = digestWeekday; self.digestHour = digestHour
        self.digestOn = digestOn; self.calendarMirror = calendarMirror; self.icloudBackup = icloudBackup
        self.haptics = haptics; self.lastExport = lastExport; self.deniedBannerDismissed = deniedBannerDismissed
        self.collapsed = collapsed; self.firstRunDone = firstRunDone; self.askedNotifications = askedNotifications
        self.personId = personId; self.names = names; self.toolPlans = toolPlans
    }

    private enum Keys: String, CodingKey {
        case leadDays, digestWeekday, digestHour, digestOn, calendarMirror, icloudBackup, haptics, lastExport
        case deniedBannerDismissed, collapsed, firstRunDone, askedNotifications, personId, names, toolPlans
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let d = Settings()
        leadDays = (try? c.decodeIfPresent(Int.self, forKey: .leadDays)) ?? d.leadDays
        digestWeekday = (try? c.decodeIfPresent(Int.self, forKey: .digestWeekday)) ?? d.digestWeekday
        digestHour = (try? c.decodeIfPresent(Int.self, forKey: .digestHour)) ?? d.digestHour
        digestOn = (try? c.decodeIfPresent(Bool.self, forKey: .digestOn)) ?? d.digestOn
        calendarMirror = (try? c.decodeIfPresent(Bool.self, forKey: .calendarMirror)) ?? d.calendarMirror
        icloudBackup = (try? c.decodeIfPresent(Bool.self, forKey: .icloudBackup)) ?? d.icloudBackup
        haptics = (try? c.decodeIfPresent(Bool.self, forKey: .haptics)) ?? d.haptics
        lastExport = try? c.decodeIfPresent(LastExport.self, forKey: .lastExport)
        deniedBannerDismissed = (try? c.decodeIfPresent(Bool.self, forKey: .deniedBannerDismissed)) ?? d.deniedBannerDismissed
        collapsed = (try? c.decodeIfPresent([String].self, forKey: .collapsed)) ?? d.collapsed
        firstRunDone = (try? c.decodeIfPresent(Bool.self, forKey: .firstRunDone)) ?? d.firstRunDone
        askedNotifications = (try? c.decodeIfPresent(Bool.self, forKey: .askedNotifications)) ?? d.askedNotifications
        personId = (try? c.decodeIfPresent(String.self, forKey: .personId)) ?? d.personId
        names = try? c.decodeIfPresent(NameState.self, forKey: .names)
        toolPlans = (try? c.decodeIfPresent([ToolPlan].self, forKey: .toolPlans)) ?? []
    }
}

public let DEFAULT_SETTINGS = Settings()

public struct Stored: Codable, Equatable, Sendable {
    public var people: [Person]
    public var anchors: [Anchor]
    public var playbooks: [Playbook]
    public var tracks: [Track]
    public var instances: [StepInstance]
    public var documents: [DocumentRecord]
    public var settings: Settings
    public var moves: Moves

    public init(plan: Plan = EMPTY_PLAN, settings: Settings = DEFAULT_SETTINGS, moves: Moves = [:]) {
        people = plan.people; anchors = plan.anchors; playbooks = plan.playbooks; tracks = plan.tracks
        instances = plan.instances; documents = plan.documents; self.settings = settings; self.moves = moves
    }

    public var plan: Plan {
        get { Plan(people: people, anchors: anchors, playbooks: playbooks, tracks: tracks, instances: instances, documents: documents) }
        set { people = newValue.people; anchors = newValue.anchors; playbooks = newValue.playbooks
              tracks = newValue.tracks; instances = newValue.instances; documents = newValue.documents }
    }
}

public let EMPTY_PLAN = Plan(people: [ME_PERSON], anchors: [], playbooks: [], tracks: [], instances: [], documents: [])

public let BACKUP_FORMAT = "paper-works-backup"
/// Backups exported before the rename to Paper Works.
private let LEGACY_FORMATS = ["life-chapters-backup"]
public let BACKUP_VERSION = 3

/// Version 3 adds `settings` and `moves`; pass them for a full snapshot.
public func serializePlan(_ plan: Plan, _ now: CivilDate, settings: Settings? = nil, moves: Moves? = nil) -> String {
    let encoder = JSONEncoder()
    func object<T: Encodable>(_ v: T) -> Any? {
        (try? encoder.encode(v)).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }
    guard var obj = object(plan) as? [String: Any] else { return "{}" }
    obj["format"] = BACKUP_FORMAT
    obj["version"] = BACKUP_VERSION
    obj["exportedOn"] = now
    if let settings, let o = object(settings) { obj["settings"] = o }
    if let moves, let o = object(moves) { obj["moves"] = o }
    let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    return out.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}

public func serializeStored(_ stored: Stored, _ now: CivilDate) -> String {
    serializePlan(stored.plan, now, settings: stored.settings, moves: stored.moves)
}

public enum ParsedBackup: Equatable, Sendable {
    case ok(Plan)
    case failure(String)
}

public enum ParsedSnapshot: Equatable, Sendable {
    case ok(Plan, settings: Settings?, moves: Moves?)
    case failure(String)
}

/// Like `parseBackup`, plus the settings and moves a version 3 file carries.
public func parseSnapshot(_ text: String) -> ParsedSnapshot {
    switch parseBackup(text) {
    case .failure(let e): return .failure(e)
    case .ok(let plan):
        let o = (text.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:]
        func decode<T: Decodable>(_ key: String, _: T.Type) -> T? {
            o[key].flatMap { try? JSONSerialization.data(withJSONObject: $0) }.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
        }
        return .ok(plan, settings: decode("settings", Settings.self), moves: decode("moves", Moves.self))
    }
}

/// Reads a backup file. Shape-checks only; playbooks re-validate on use.
public func parseBackup(_ text: String) -> ParsedBackup {
    guard let data = text.data(using: .utf8),
          let raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
        return .failure("This file isn't JSON.")
    }
    guard let o = raw as? [String: Any], let format = o["format"] as? String,
          format == BACKUP_FORMAT || LEGACY_FORMATS.contains(format) else {
        return .failure("This isn't a Paper Works backup.")
    }
    guard let version = o["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(),
          version.intValue <= BACKUP_VERSION else {
        return .failure("This backup is from a newer version of the app.")
    }
    func list<T: Decodable>(_ key: String, _: T.Type) -> [T]? {
        guard let arr = o[key] as? [Any],
              let d = try? JSONSerialization.data(withJSONObject: arr) else { return nil }
        return try? JSONDecoder().decode([T].self, from: d)
    }
    for key in ["anchors", "playbooks", "tracks", "instances", "documents"] where !(o[key] is [Any]) {
        return .failure("The backup is missing its \(key).")
    }
    guard let anchors = list("anchors", Anchor.self), let playbooks = list("playbooks", Playbook.self),
          let tracks = list("tracks", Track.self), let instances = list("instances", StepInstance.self),
          let documents = list("documents", DocumentRecord.self) else {
        return .failure("The backup couldn't be read.")
    }
    let people = list("people", Person.self) ?? []
    return .ok(Plan(people: people.isEmpty ? [ME_PERSON] : people, anchors: anchors, playbooks: playbooks,
                    tracks: tracks, instances: instances, documents: documents))
}

/// iCloud dated files past the window; `latest.json` and anything else is left alone.
public func dailiesToPrune(_ names: [String], _ today: CivilDate, days: Int = KEEP_DAYS) -> [String] {
    let oldest = addDays(today, -(days - 1))
    return names.filter { n in dailyDay(n).map { $0 < oldest } ?? false }.sorted()
}
