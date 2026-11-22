import Testing
@testable import PaperWorksCore

private let events: [LifeEvent] = [
    LifeEvent(id: "b", label: "Born", date: "1991-04-12", source: .anchor),
    LifeEvent(id: "m", label: "Migrated", date: "2024-09-14", source: .anchor),
    LifeEvent(id: "c", label: "Citizenship eligible", date: "2029-09-14", source: .derived),
]

struct ChaptersTests {
    @Test func foldsEventsIntoContiguousIntervalsLastOpenEnded() {
        let chapters = deriveChapters(events, "2026-09-26")
        #expect(chapters.map(\.start) == ["1991-04-12", "2024-09-14", "2029-09-14"])
        #expect(chapters.map(\.end) == ["2024-09-14", "2029-09-14", nil])
    }

    @Test func marksExactlyOneChapterCurrent() {
        let chapters = deriveChapters(events, "2026-09-26")
        #expect(chapters.filter(\.isCurrent).count == 1)
        #expect(currentChapter(chapters)?.label == "Migrated")
    }

    @Test func sortsUnorderedInput() {
        #expect(deriveChapters(events.reversed(), "2026-09-26")[0].label == "Born")
    }

    @Test func noCurrentChapterWhenEveryEventIsAhead() {
        #expect(currentChapter(deriveChapters(events, "1980-01-01")) == nil)
    }

    @Test func boundaryBelongsToLaterChapter() {
        #expect(currentChapter(deriveChapters(events, "2024-09-14"))?.label == "Migrated")
    }

    @Test func visitSitsOnLineWithoutOpeningChapter() {
        let anchors = [
            Anchor(id: "b", kind: "born", label: "Born", date: "1990-01-01"),
            Anchor(id: "v", kind: "visit", label: "Visitors arrive", place: "Mom and Dad", date: "2026-10-01"),
        ]
        let nodes = timelineNodes(anchors, [], [], "2026-09-27")
        #expect(nodes.map(\.label).contains("Mom and Dad arrive"))
        #expect(eventChapters(nodes, "2026-09-27").map(\.eventId) == ["b"])
    }
}
