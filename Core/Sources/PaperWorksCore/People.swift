import Foundation

public let ME = "me"
public let ME_PERSON = Person(id: ME, name: "Me")

/// Records from before people existed belong to "me".
public func ownerOf(_ personId: String?) -> String { personId ?? ME }
public func ownerOf(_ a: Anchor) -> String { a.personId ?? ME }
public func ownerOf(_ d: DocumentRecord) -> String { d.personId ?? ME }

/// Kinds that tie two people together, and what the other side sees.
public let LINKED_KINDS: [String: String] = ["child-born": "born", "married": "married"]

public func isLinkedKind(_ kind: String) -> Bool { LINKED_KINDS[kind] != nil }

/// The date a plan opened by `event` hangs on; nil when that date doesn't exist yet.
public func countsFrom(_ pb: Playbook, _ event: Anchor, _ anchors: [Anchor]) -> Anchor? {
    switch opens(event.kind, pb) {
    case .`self`: return anchors.first { $0.id == event.id } ?? event
    case .born: return anchors.first { $0.kind == "born" && ownerOf($0) == ownerOf(event) }
    case .child:
        guard let link = event.linkId else { return nil }
        return anchors.first { $0.kind == "born" && $0.linkId == link }
    case nil: return nil
    }
}

/// Who the person menu lists: Me, whoever is on screen, and anyone with an event of their own.
public func menuPeople(_ people: [Person], _ anchors: [Anchor], showing: String) -> [Person] {
    people.filter { p in p.id == ME || p.id == showing || anchors.contains { ownerOf($0) == p.id && $0.linkId == nil } }
}

public func trackOwner(_ track: Track, _ anchors: [Anchor]) -> String {
    if let p = track.personId { return p }
    if let a = anchors.first(where: { $0.id == track.anchorId }) { return ownerOf(a) }
    return ME
}

public struct Scoped: Equatable, Sendable {
    public var anchors: [Anchor]
    public var tracks: [Track]
    public var instances: [StepInstance]
    public var documents: [DocumentRecord]
}

/// One person's board. A linked event names the other person by their current name.
public func scopeTo(_ personId: String, _ plan: Plan) -> Scoped {
    func nameOf(_ id: String) -> String? { plan.people.first { $0.id == id }?.name }
    let anchors = plan.anchors.filter { ownerOf($0) == personId }.map { a -> Anchor in
        guard let w = a.withPersonId, a.kind != "born" else { return a }
        var c = a
        c.place = nameOf(w) ?? a.place
        return c
    }
    let tracks = plan.tracks.filter { trackOwner($0, plan.anchors) == personId }
    let ids = Set(tracks.map(\.id))
    return Scoped(anchors: anchors, tracks: tracks,
                  instances: plan.instances.filter { ids.contains($0.trackId) },
                  documents: plan.documents.filter { ownerOf($0) == personId })
}

/// The same event as the other person sees it: "Ava born" on mine is "Born" on hers.
public func mirrorOf(_ anchor: Anchor, id: String, otherId: String, ownName: String) -> Anchor {
    let kind = LINKED_KINDS[anchor.kind] ?? anchor.kind
    return Anchor(id: id, kind: kind, label: kind == "born" ? "Born" : anchor.label,
                  place: kind == "born" ? nil : ownName, location: anchor.location,
                  date: anchor.date, precision: anchor.precision,
                  personId: otherId, withPersonId: ownerOf(anchor), linkId: anchor.linkId)
}
