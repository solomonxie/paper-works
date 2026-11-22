import Foundation

enum PersonMode: String, Hashable, Sendable { case new, link, rename }

/// One route table for the one stack (src/navigation/routes.ts).
enum Route: Hashable {
    case timeline
    case chapter(eventId: String)
    case anchorEdit(anchorId: String?, kind: String?)
    case settings
    case reminders
    case backups
    case sources
    case about
    case person(mode: PersonMode, personId: String?)
    case library
    case playbook(playbookId: String, trackId: String?)
    case document(documentId: String)
    case step(instanceId: String)
    case firstRun
    case names(planId: String)
    case namesHistory(planId: String)
}
