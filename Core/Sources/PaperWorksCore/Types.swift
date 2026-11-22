import Foundation

/// A calendar date with no time and no zone: `YYYY-MM-DD`, compared lexically.
public typealias CivilDate = String

public enum DatePrecision: String, Codable, Sendable { case year, month, day }

public struct Anchor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: String
    public var label: String
    public var place: String?
    public var location: String?
    public var date: CivilDate
    public var precision: DatePrecision
    public var end: CivilDate?
    public var purpose: String?
    public var note: String?
    public var personId: String?
    public var withPersonId: String?
    public var linkId: String?

    public init(id: String, kind: String, label: String, place: String? = nil, location: String? = nil,
                date: CivilDate, precision: DatePrecision = .day, end: CivilDate? = nil, purpose: String? = nil,
                note: String? = nil, personId: String? = nil, withPersonId: String? = nil, linkId: String? = nil) {
        self.id = id; self.kind = kind; self.label = label; self.place = place; self.location = location
        self.date = date; self.precision = precision; self.end = end; self.purpose = purpose; self.note = note
        self.personId = personId; self.withPersonId = withPersonId; self.linkId = linkId
    }
}

public struct Person: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct LifeEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable { case anchor, derived }
    public var id: String
    public var label: String
    public var date: CivilDate
    public var source: Source
    public var anchorId: String?
    public var chapterLabel: String?
}

public struct Chapter: Codable, Equatable, Sendable {
    public var eventId: String
    public var label: String
    public var start: CivilDate
    public var end: CivilDate?
    public var isCurrent: Bool
}

/// Whole years of age; `to` inclusive, open if absent.
public struct AgeRange: Codable, Equatable, Sendable {
    public var from: Int
    public var to: Int?
}

public struct StepTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var offsetDays: Int
    public var endOffsetDays: Int?
    public var purposes: [String]?
    public var durationDays: Int
    public var validForDays: Int?
    public var dependsOn: [String]
    public var documents: [String]
    public var prepare: [String]
    public var howTo: String?
    public var ages: AgeRange?
    public var conditions: [String]?
    public var redoOf: String?

    public init(id: String, title: String, offsetDays: Int, endOffsetDays: Int? = nil, purposes: [String]? = nil,
                durationDays: Int, validForDays: Int? = nil, dependsOn: [String] = [], documents: [String] = [],
                prepare: [String] = [], howTo: String? = nil, ages: AgeRange? = nil, conditions: [String]? = nil,
                redoOf: String? = nil) {
        self.id = id; self.title = title; self.offsetDays = offsetDays; self.endOffsetDays = endOffsetDays
        self.purposes = purposes; self.durationDays = durationDays; self.validForDays = validForDays
        self.dependsOn = dependsOn; self.documents = documents; self.prepare = prepare; self.howTo = howTo
        self.ages = ages; self.conditions = conditions; self.redoOf = redoOf
    }
}

public struct Source: Codable, Equatable, Sendable {
    public var title: String
    public var url: String
}

public struct Playbook: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var summary: String?
    public var region: String?
    public var country: String?
    public var province: String?
    public var family: String?
    public var citizen: String?
    public var leaving: Bool?
    public var anchorKind: String
    public var ages: AgeRange?
    public var conditions: [String]?
    public var reviewedAt: CivilDate
    public var version: Int?
    public var sources: [Source]?
    public var steps: [StepTemplate]
}

public enum InstanceStatus: String, Codable, Sendable { case pending, done, skipped, snoozed }

public struct StepInstance: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var trackId: String
    public var stepId: String
    public var status: InstanceStatus
    public var completedOn: CivilDate?
    public var snoozedUntil: CivilDate?
    public var dueOverride: CivilDate?
    public var note: String?
    public var checkedDocuments: [String]
    public var checkedPrepare: [String]

    public init(id: String, trackId: String, stepId: String, status: InstanceStatus = .pending, completedOn: CivilDate? = nil,
                snoozedUntil: CivilDate? = nil, dueOverride: CivilDate? = nil, note: String? = nil,
                checkedDocuments: [String] = [], checkedPrepare: [String] = []) {
        self.id = id; self.trackId = trackId; self.stepId = stepId; self.status = status; self.completedOn = completedOn
        self.snoozedUntil = snoozedUntil; self.dueOverride = dueOverride; self.note = note
        self.checkedDocuments = checkedDocuments; self.checkedPrepare = checkedPrepare
    }
}

public struct Track: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var playbookId: String
    public var personId: String?
    public var anchorId: String?
    public var anchorEventDate: CivilDate
    public var anchorEnd: CivilDate?
    public var purpose: String?
    public var extraSteps: [StepTemplate]?
    public var extraDependsOn: [String: [String]]?

    public init(id: String, playbookId: String, personId: String? = nil, anchorId: String? = nil, anchorEventDate: CivilDate,
                anchorEnd: CivilDate? = nil, purpose: String? = nil, extraSteps: [StepTemplate]? = nil,
                extraDependsOn: [String: [String]]? = nil) {
        self.id = id; self.playbookId = playbookId; self.personId = personId; self.anchorId = anchorId
        self.anchorEventDate = anchorEventDate; self.anchorEnd = anchorEnd; self.purpose = purpose
        self.extraSteps = extraSteps; self.extraDependsOn = extraDependsOn
    }
}

public struct ScheduledStep: Codable, Equatable, Sendable {
    public var stepId: String
    public var instanceId: String
    public var title: String
    public var status: InstanceStatus
    public var dueBy: CivilDate
    public var startBy: CivilDate
    public var earliestStart: CivilDate?
    public var atRisk: Bool
    public var blockedBy: [String]
    public var expiresOn: CivilDate?
    public var snoozedUntil: CivilDate?
    public var blockedByLate: [String]
}

public struct DocumentRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var personId: String?
    public var issuedOn: CivilDate?
    public var expiresOn: CivilDate?
    public var number: String?
    public var noExpiry: Bool?
    public var scanPath: String?

    public init(id: String, name: String, personId: String? = nil, issuedOn: CivilDate? = nil, expiresOn: CivilDate? = nil,
                number: String? = nil, noExpiry: Bool? = nil, scanPath: String? = nil) {
        self.id = id; self.name = name; self.personId = personId; self.issuedOn = issuedOn; self.expiresOn = expiresOn
        self.number = number; self.noExpiry = noExpiry; self.scanPath = scanPath
    }
}

/// A reflow the user didn't make, shown as ▲▼ for a while.
public struct Move: Codable, Equatable, Sendable {
    public var from: CivilDate
    public var to: CivilDate
    public var on: CivilDate
    public var cause: String

    public init(from: CivilDate, to: CivilDate, on: CivilDate, cause: String) {
        self.from = from; self.to = to; self.on = on; self.cause = cause
    }
}

public typealias Moves = [String: Move]

/// Everything the user owns. Bundled playbooks are not here.
public struct Plan: Codable, Equatable, Sendable {
    public var people: [Person]
    public var anchors: [Anchor]
    public var playbooks: [Playbook]
    public var tracks: [Track]
    public var instances: [StepInstance]
    public var documents: [DocumentRecord]

    public init(people: [Person], anchors: [Anchor] = [], playbooks: [Playbook] = [], tracks: [Track] = [],
                instances: [StepInstance] = [], documents: [DocumentRecord] = []) {
        self.people = people; self.anchors = anchors; self.playbooks = playbooks
        self.tracks = tracks; self.instances = instances; self.documents = documents
    }
}
