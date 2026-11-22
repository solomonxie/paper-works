import Testing
@testable import PaperWorksCore

@Suite struct PeopleTests {
    @Test func menuListsOnlyPeopleWithOwnEvents() {
        let people = [Person(id: ME, name: "Me"), Person(id: "c", name: "Christine"), Person(id: "a", name: "Ava")]
        let wedding = Anchor(id: "w", kind: "married", label: "Married", date: "2022-06-22", personId: "c", linkId: "l")
        let job = Anchor(id: "j", kind: "first-job", label: "First job", date: "2010-01-01", personId: "a")
        #expect(menuPeople(people, [wedding, job], showing: ME).map(\.name) == ["Me", "Ava"])
        #expect(menuPeople(people, [wedding, job], showing: "c").map(\.name) == ["Me", "Christine", "Ava"])
    }
}
