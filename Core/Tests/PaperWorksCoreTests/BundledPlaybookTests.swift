import Foundation
import Testing
@testable import PaperWorksCore

struct BundledPlaybookTests {
    @Test(arguments: bundledPlaybooks)
    func passesImportValidation(_ playbook: Playbook) throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(playbook))
        #expect(validatePlaybook(json).isOk, "\(playbook.id): \(validatePlaybook(json).error ?? "")")
    }

    @Test(arguments: bundledPlaybooks)
    func schedulesWithoutAStepAlreadyAtRisk(_ playbook: Playbook) throws {
        let track = Track(id: "t", playbookId: playbook.id, anchorEventDate: "2028-02-01")
        #expect(try schedule(playbook, track, []).filter(\.atRisk).map(\.stepId) == [], "\(playbook.id)")
    }
}
