import Foundation

/// Events fold into the contiguous intervals between them. The last chapter is
/// open-ended, and exactly one chapter contains today unless every event is ahead.
public func deriveChapters(_ events: [LifeEvent], _ now: CivilDate) -> [Chapter] {
    let sorted = events.sorted { $0.date < $1.date }
    return sorted.enumerated().map { i, event in
        let end: CivilDate? = i + 1 < sorted.count ? sorted[i + 1].date : nil
        return Chapter(
            eventId: event.id,
            label: event.chapterLabel ?? event.label,
            start: event.date,
            end: end,
            isCurrent: event.date <= now && (end == nil || now < end!)
        )
    }
}

public func currentChapter(_ chapters: [Chapter]) -> Chapter? { chapters.first { $0.isCurrent } }
