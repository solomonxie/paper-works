import Testing
@testable import PaperWorksCore

@Suite struct ContentTests {
    @Test func everyPlaybookHangsOffAKnownKind() {
        #expect(!bundledPlaybooks.isEmpty)
        for p in bundledPlaybooks { #expect(kindById(p.anchorKind) != nil, "\(p.id)") }
    }

    @Test func advicePhrasing() {
        for p in bundledPlaybooks {
            let text = p.steps.flatMap { [$0.title, $0.howTo ?? ""] + $0.documents + $0.prepare }.joined(separator: " ")
            #expect(text.range(of: #"\byou must\b|\brequired by law\b|\bguarantee(?!d Income Supplement)"#, options: [.regularExpression, .caseInsensitive]) == nil, "\(p.id)")
        }
    }

    @Test func whoItIsFor() {
        for p in bundledPlaybooks {
            #expect(!(p.conditions ?? []).isEmpty, "\(p.id)")
            if ["born", "child-born"].contains(p.anchorKind) { #expect(p.ages != nil, "\(p.id)") }
        }
    }

    @Test func reviewDateAndSources() {
        for p in bundledPlaybooks {
            #expect(p.reviewedAt.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil, "\(p.id)")
            #expect(!(p.sources ?? []).isEmpty, "\(p.id)")
        }
    }

    @Test func provinces() {
        let provincial = bundledPlaybooks.filter { $0.province != nil }
        let keys = provincial.map { "\($0.family ?? ""):\($0.province!)" }
        #expect(provincial.allSatisfy { $0.family != nil })
        #expect(Set(keys).count == keys.count)
        func families(_ c: String) -> [String] { provincial.filter { $0.province == c }.compactMap(\.family).sorted() }
        #expect(families("BC") == families("ON"))
    }

    @Test func countries() {
        let stages = ["marriage", "pregnancy", "newborn", "early-years", "school-years", "high-school", "coming-of-age", "retirement"]
        let cn = bundledPlaybooks.filter { $0.country == "CN" }.compactMap(\.family)
        #expect(stages.filter { !cn.contains($0) } == [])
        #expect(bundledPlaybooks.filter { $0.country == nil }.isEmpty)
    }
}
