import Testing
@testable import PaperWorksCore

@Suite struct FormatTests {
    @Test func formatAgesRanges() {
        #expect(formatAges(AgeRange(from: 16, to: nil)) == "age 16+")
        #expect(formatAges(AgeRange(from: 18, to: 18)) == "age 18")
        #expect(formatAges(AgeRange(from: 4, to: 5)) == "ages 4–5")
    }
}
