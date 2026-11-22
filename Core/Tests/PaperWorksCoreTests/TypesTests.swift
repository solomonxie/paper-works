import Foundation
import Testing
@testable import PaperWorksCore

@Test func bundledPlaybooksDecode() throws {
    let url = try #require(Bundle.module.url(forResource: "playbooks", withExtension: "json"))
    let playbooks = try JSONDecoder().decode([Playbook].self, from: Data(contentsOf: url))
    #expect(playbooks.count == 89)
}
