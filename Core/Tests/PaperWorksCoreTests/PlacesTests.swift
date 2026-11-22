import Testing
@testable import PaperWorksCore

private func labels(_ q: String) -> [String] { searchPlaces(q).map(placeLabel) }

@Suite struct PlacesTests {
    @Test func biggestPrefixFirst() { #expect(labels("toron")[0] == "Toronto, Ontario, Canada") }

    @Test func chinesePlaces() {
        #expect(labels("南昌")[0].hasPrefix("Nanchang, Jiangxi"))
        #expect(labels("多伦多") == [])
    }

    @Test func englishNames() {
        #expect(labels("montréal")[0] == "Montreal, Quebec, Canada")
        #expect(labels("sao paulo")[0] == "Sao Paulo, Brazil")
        #expect(labels("tokyo")[0] == "Tokyo, Japan")
    }

    @Test func nearFirst() {
        #expect(labels("richmond")[0] == "Richmond, Virginia, United States")
        #expect(searchPlaces("richmond", limit: 8, near: "Canada").map(placeLabel)[0] == "Richmond, British Columbia, Canada")
    }

    @Test func narrowsAfterComma() {
        #expect(labels("london, ontario")[0] == "London, Ontario, Canada")
        #expect(labels("london")[0].contains("United Kingdom"))
    }

    @Test func smallTowns() { #expect(labels("canmore")[0].hasPrefix("Canmore, Alberta")) }
    @Test func emptyQuery() { #expect(searchPlaces("  ").isEmpty) }
    @Test func shortLabel() { #expect(placeShort("Toronto, Ontario, Canada") == "Toronto") }
}
