import Testing
@testable import PaperWorksCore

private func at(_ date: String, _ location: String?, _ kind: String = "moved-city") -> Anchor {
    Anchor(id: date, kind: kind, label: "Moved city", location: location, date: date)
}
private let BC = Where(country: "CA", province: "BC")

@Suite struct RegionsTests {
    @Test func whereOfReads() {
        #expect(whereOf("Vancouver, British Columbia, Canada") == BC)
        #expect(whereOf("Nanchang, Jiangxi, China") == Where(country: "CN"))
        #expect(whereOf("London, England, United Kingdom") == Where(country: "GB"))
        #expect(whereOf("进贤谢家村").country == "CN")
    }

    @Test func livesIn_() {
        let a = [at("2020-01-01", "Toronto, Ontario, Canada"), at("2024-06-01", "Burnaby, British Columbia, Canada"), at("2030-01-01", "Calgary, Alberta, Canada")]
        #expect(livesIn(a, "2026-09-27") == BC)
        #expect(livesIn([], "2026-09-27") == Where())
        let b = [at("2020-01-01", "Vancouver, British Columbia, Canada"), at("2024-06-01", "Toronto, Ontario, Canada", "married")]
        #expect(livesIn(b, "2026-09-27") == BC)
    }

    @Test func decided() {
        let moved = at("2023-01-02", "Vancouver, Washington, United States", "migrated")
        let born = at("1988-08-06", "Nanchang, Jiangxi, China", "born")
        #expect(decidedBy(born, [born, moved], "2026-09-27") == moved)
        #expect(countryName(whereOf(moved.location).country) == "United States")
        let wedding = at("2022-06-22", "Toronto, Ontario, Canada", "married")
        #expect(decidedBy(wedding, [moved], "2026-09-27") == wedding)
    }

    private func pb(_ id: String, country: String? = nil, province: String? = nil, family: String? = nil,
                    citizen: String? = nil, leaving: Bool? = nil, kind: String = "born") -> Playbook {
        Playbook(id: id, title: id, country: country, province: province, family: family, citizen: citizen, leaving: leaving,
                 anchorKind: kind, reviewedAt: "2026-01-01", steps: [])
    }

    @Test func fitsAndTwins() {
        let on = pb("on", country: "CA", province: "ON", family: "school-years")
        let bc = pb("bc", country: "CA", province: "BC", family: "school-years")
        let cn = pb("cn", country: "CN", family: "school-years")
        let federal = pb("ca", country: "CA")
        #expect(fits(federal, BC)); #expect(!fits(on, BC)); #expect(!fits(cn, BC))
        #expect(fits(cn, Where(country: "CN"))); #expect(fits(on, Where()))
        #expect(twinFor(on, BC, [on, bc, cn])?.id == "bc")
        #expect(twinFor(bc, Where(country: "CN"), [on, bc, cn])?.id == "cn")
        #expect(twinFor(bc, BC, [on, bc, cn]) == nil)
    }

    @Test func weddingVsBirth() {
        let wedding = Anchor(id: "w", kind: "married", label: "Married", location: "Toronto, Ontario, Canada", date: "2022-06-22")
        let born = Anchor(id: "b", kind: "born", label: "Born", location: "进贤谢家村", date: "1988-08-06")
        #expect(whereAt(wedding, BC) == Where(country: "CA", province: "ON"))
        #expect(whereAt(born, BC) == BC)
        #expect(whereAt(born, Where()).country == "CN")
        #expect(whereWhy(wedding, BC) == "Married in Ontario")
        #expect(whereWhy(born, BC) == "lives in British Columbia")
    }

    @Test func weddingOpensOntarioPlan() {
        let ids = plansFor(kind: "married", location: "Toronto, Ontario, Canada", BC, bundledPlaybooks).map(\.id)
        #expect(ids == ["marriage-on"])
    }

    @Test func leaving() {
        let exit = pb("exit", country: "CN", leaving: true, kind: "migrated")
        let arrive = pb("arrive", country: "CA", province: "BC", kind: "migrated")
        let born = at("1988-08-06", "Nanchang, Jiangxi, China", "born")
        let toBC = at("2023-01-02", "Vancouver, British Columbia, Canada", "migrated")
        #expect(plansFor(toBC, BC, [exit, arrive], [born, toBC]).map(\.id) == ["exit", "arrive"])
        let within = at("2010-01-02", "Shanghai, China", "migrated")
        #expect(plansFor(within, Where(), [exit, arrive], [born, within]).isEmpty)
    }

    @Test func visaPlans() {
        let cnToJp = pb("cn-jp", country: "JP", citizen: "CN", kind: "trip")
        let phToJp = pb("ph-jp", country: "JP", citizen: "PH", kind: "trip")
        let cnToEu = pb("cn-eu", country: "SCHENGEN", citizen: "CN", kind: "trip")
        let all = [cnToJp, phToJp, cnToEu]
        let born = at("1988-08-06", "Nanchang, Jiangxi, China", "born")
        let tokyo = at("2027-04-01", "Tokyo, Japan", "trip")
        #expect(plansFor(tokyo, BC, all, [born, tokyo]).map(\.id) == ["cn-jp", "ph-jp"])
        let phBorn = at("1990-01-01", "Manila, National Capital Region, Philippines", "born")
        #expect(plansFor(tokyo, BC, all, [phBorn, tokyo]).map(\.id) == ["ph-jp", "cn-jp"])
        let paris = at("2027-05-01", "Paris, Île-de-France, France", "trip")
        #expect(plansFor(paris, BC, all, [born, paris]).map(\.id) == ["cn-eu"])
        let visit = at("2027-06-01", "Tokyo, Japan", "visit")
        #expect(plansFor(visit, BC, all, [born, visit]).map(\.id) == ["cn-jp", "ph-jp"])
    }
}
