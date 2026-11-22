import Testing
@testable import PaperWorksCore

private let BC = Where(country: "CA", province: "BC")
private func ids(_ kind: String) -> [String] { plansFor(kind: kind, BC, bundledPlaybooks).map(\.id) }

@Suite struct KindsTests {
    @Test func bornPlans() {
        #expect(ids("school-start") == ["school-years-bc"])
        #expect(ids("retire").sorted() == ["retire-ca", "retirement-bc"])
        #expect(ids("child-born").sorted() == ["early-years-bc", "newborn-bc"])
    }

    @Test func everyEventHasPlan() {
        #expect(ids("graduated") == ["graduated-ca"])
        #expect(ids("first-job") == ["first-job-ca"])
        #expect(ids("new-job") == ["first-job-ca"])
        #expect(ids("moved-city") == ["moved-city-bc"])
        #expect(ids("home-bought") == ["home-bought-bc"])
        for k in ["job-lost", "business-started", "home-sold", "car-bought", "cohabiting", "separated", "caregiving", "family-death", "pr-landed", "visa-granted"] {
            #expect(!ids(k).isEmpty, "\(k)")
        }
    }

    @Test func newJobOpens() {
        #expect(opens("new-job", anchorKind: "first-job") == .`self`)
        #expect(opens("new-job", anchorKind: "born", family: "retirement") == nil)
    }

    @Test func titles() {
        #expect(anchorTitle("migrated", "Relocated to a country", "Canada") == "Relocated to Canada")
        #expect(anchorTitle("born", "Born", "Xi'an") == "Born · Xi'an")
        #expect(anchorTitle("born", "Born") == "Born")
        #expect(kindLabel("nope") == "nope")
    }

    @Test func visaPlansInBundle() {
        func at(_ kind: String, _ date: String, _ loc: String) -> Anchor { Anchor(id: "\(kind)-\(date)", kind: kind, label: kind, location: loc, date: date) }
        let born = at("born", "1988-08-06", "Nanchang, Jiangxi, China")
        func visa(_ a: Anchor) -> [String] { plansFor(a, BC, bundledPlaybooks, [born, a]).map(\.id).filter { $0.hasPrefix("visa-") }.sorted() }
        #expect(visa(at("trip", "2027-04-01", "Tokyo, Tokyo, Japan")) == ["visa-jp-cn", "visa-jp-ph"])
        #expect(visa(at("trip", "2027-05-01", "Rome, Latium, Italy")) == ["visa-schengen-cn", "visa-schengen-ph"])
        #expect(visa(at("trip", "2027-06-01", "Manila, National Capital Region, Philippines")) == ["visa-ph-cn"])
        let us = at("trip", "2027-08-01", "New York, New York, United States")
        #expect(plansFor(us, BC, bundledPlaybooks, [born, us]).map(\.id).filter { $0.hasPrefix("visa-") } == ["visa-us-cn", "visa-us-ph"])
        #expect(visa(at("visit", "2027-07-01", "Vancouver, British Columbia, Canada")) == ["visa-ca-cn", "visa-ca-ph"])
    }
}
