import Foundation

/// The demo plan's data (demo/plan.ts). Recent dates are relative to today so it never goes stale.
public enum DemoDate: Equatable, Sendable {
    case fixed(CivilDate)
    /// `years` from this year, on `MM-DD`.
    case yearly(years: Int, on: String)
    case days(Int)
}

public func demoDate(_ d: DemoDate, _ now: CivilDate) -> CivilDate {
    switch d {
    case .fixed(let s): return s
    case .days(let n): return addDays(now, n)
    case .yearly(let years, let on): return "\((Int(now.prefix(4)) ?? 0) + years)-\(on)"
    }
}

public struct DemoEvent: Sendable {
    public var kind: String
    public var label: String
    public var date: DemoDate
    public var precision: DatePrecision
    public var place: String?
    public var location: String?
    public var note: String?
    /// Bundled playbook ids to start on this event.
    public var plans: [String] = []
    /// Spouse or child: gets a board of their own.
    public var with: String?
}

public struct DemoPersonPlan: Sendable {
    public var person: String
    /// Playbooks on that person's Born.
    public var plans: [String]
}

public struct DemoDocument: Sendable {
    public var id: String
    public var name: String
    /// Whose; nil means Me.
    public var person: String?
    public var issuedOn: DemoDate?
    public var expiresOn: DemoDate?
    public var number: String?
    public var noExpiry: Bool?

    /// The record for `owner` (the id of `person`, or ME).
    public func record(owner: String, now: CivilDate) -> DocumentRecord {
        DocumentRecord(id: id, name: name, personId: owner, issuedOn: issuedOn.map { demoDate($0, now) },
                       expiresOn: expiresOn.map { demoDate($0, now) }, number: number, noExpiry: noExpiry, scanPath: nil)
    }
}

private let XIAN = "Xi'an, Shaanxi, China"
private let VANCOUVER = "Vancouver, British Columbia, Canada"

public let DEMO_EVENTS: [DemoEvent] = [
    DemoEvent(kind: "born", label: "Born", date: .fixed("1991-04-12"), precision: .day, location: XIAN),
    DemoEvent(kind: "graduated", label: "Graduated", date: .fixed("2013-07-01"), precision: .year,
              place: "BSc Computer Science", location: XIAN,
              note: "Rain all morning, sun for the photo. Nobody could find the gowns."),
    DemoEvent(kind: "first-job", label: "First job", date: .fixed("2013-09-02"), precision: .month,
              place: "Junior developer", location: "Shenzhen, Guangdong, China",
              note: "A desk by the window and a lead who answered every question twice without sighing."),
    DemoEvent(kind: "married", label: "Married", date: .fixed("2019-06-01"), precision: .day, location: XIAN,
              note: "Forty guests, one rainstorm, and my grandmother dancing to the end.", with: "Sam"),
    DemoEvent(kind: "visa-granted", label: "Permit or visa granted", date: .yearly(years: -2, on: "07-30"),
              precision: .day, place: "Open work permit", plans: ["permit-ca"]),
    DemoEvent(kind: "migrated", label: "Relocated to a country", date: .yearly(years: -2, on: "09-14"),
              precision: .day, place: "Canada", location: VANCOUVER,
              note: "Two suitcases and a borrowed car. The first night we slept on the floor of an empty flat.",
              plans: ["relocation-bc"]),
    DemoEvent(kind: "child-born", label: "Child born", date: .yearly(years: -1, on: "03-18"), precision: .day,
              location: VANCOUVER, note: "Born at 4:12 in the morning, eight minutes after the snow started.",
              with: "Ava"),
    DemoEvent(kind: "car-bought", label: "Bought a car", date: .yearly(years: -1, on: "06-20"), precision: .day,
              place: "Used Corolla", location: VANCOUVER, plans: ["car-bought-bc"]),
    DemoEvent(kind: "trip", label: "Trip abroad", date: .days(95), precision: .day, place: "China", location: XIAN),
    DemoEvent(kind: "visa-lodge", label: "Apply for permanent residence", date: .days(560), precision: .day,
              place: "Express Entry", plans: ["skilled-migration-ca"]),
]

public let DEMO_PERSON_PLANS: [DemoPersonPlan] = [
    DemoPersonPlan(person: "Ava", plans: ["newborn-bc", "early-years-bc", "school-years-bc"]),
]

/// Steps marked done on a given day, matched by title (case-insensitive regex); everything already due is done too.
public let DEMO_DONE: [(title: String, on: DemoDate)] = [
    ("eligibility and the CRS", .days(-120)),
    ("passport validity", .days(-90)),
    ("absences|days spent outside", .yearly(years: -2, on: "10-01")),
]

/// Documents ticked off on open steps, by step title (case-insensitive regex).
public let DEMO_GATHERED: [String] = ["language test"]

public let DEMO_DOCUMENTS: [DemoDocument] = [
    DemoDocument(id: "passport", name: "Passport", issuedOn: .fixed("2016-08-02"), expiresOn: .days(150), number: "E12345678"),
    DemoDocument(id: "work-permit", name: "Work permit", issuedOn: .yearly(years: -2, on: "07-30"), expiresOn: .days(310), number: "U100482913"),
    DemoDocument(id: "drivers-licence", name: "Driver's licence", issuedOn: .yearly(years: -1, on: "05-02"), expiresOn: .yearly(years: 4, on: "04-12"), number: "7765201"),
    DemoDocument(id: "bc-services-card", name: "BC Services Card", issuedOn: .yearly(years: -2, on: "12-10"), expiresOn: .yearly(years: 3, on: "04-12")),
    DemoDocument(id: "passport", name: "Passport", person: "Ava", issuedOn: .yearly(years: -1, on: "05-20"), expiresOn: .yearly(years: 4, on: "05-20"), number: "AB408817"),
    DemoDocument(id: "birth-certificate", name: "Birth certificate", person: "Ava", issuedOn: .yearly(years: -1, on: "04-02"), noExpiry: true),
]

/// What the demo store starts from: an empty plan with the demo's first-run flags set. The app then replays
/// `DEMO_EVENTS`, `DEMO_PERSON_PLANS`, `DEMO_DONE`, `DEMO_GATHERED`, `DEMO_DOCUMENTS` through its own actions.
public func demoSeed() -> Stored {
    var settings = DEFAULT_SETTINGS
    settings.firstRunDone = true
    settings.icloudBackup = true
    settings.askedNotifications = true
    return Stored(plan: EMPTY_PLAN, settings: settings)
}
