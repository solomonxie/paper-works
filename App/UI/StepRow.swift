import SwiftUI
import PaperWorksCore

private struct PressStyle: ButtonStyle {
    @Environment(\.palette) private var p
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? p.hairline : .clear)
    }
}

/// The app's most reused row. One trailing value per state: date, "5 days late", "blocked", "not for me".
struct StepRow: View {
    let step: ScheduledStep
    var completedOn: CivilDate?
    let now: CivilDate
    var subtitle: String?
    var move: Move?
    /// Two-line form for ACT NOW: "start by Sep 20 · 5 days late".
    var detailed = false
    var onPress: (() -> Void)?
    @Environment(\.palette) private var p

    private var open: Bool { step.status == .pending || step.status == .snoozed }
    private var blocked: Bool { open && !step.blockedByLate.isEmpty }
    /// Only past due-by is red; a passed start-by is just "start now".
    private var overdue: Bool { open && !blocked && step.snoozedUntil == nil && step.dueBy < now }

    private var mark: String { step.status == .done ? "✓" : (overdue || step.atRisk ? "⚠" : "") }
    private var markColor: Color { step.status == .done ? p.done : (overdue ? p.late : p.warn) }

    private var trailing: String {
        if step.status == .done { return formatShort(step.startBy) }
        if step.status == .skipped { return "not for me" }
        if let s = step.snoozedUntil, s > now { return "snoozed \(formatSpan(diffDays(now, s)))" }
        if blocked { return "blocked" }
        if overdue { return formatRelative(step.dueBy, now: now) }
        if step.startBy <= now { return "start now" }
        return step.startBy.prefix(4) == now.prefix(4) ? formatShort(step.startBy) : formatMonth(step.startBy)
    }

    private var detailLine: String {
        if blocked { return "blocked · waiting on a late step" }
        if overdue { return "due \(formatShort(step.dueBy)) · \(formatRelative(step.dueBy, now: now))" }
        if step.startBy <= now { return "start now · due \(formatShort(step.dueBy))" }
        return "start by \(formatShort(step.startBy)) · \(formatRelative(step.startBy, now: now))"
    }

    private var spokenLabel: String {
        var parts = [step.title, step.status == .done ? "done \(formatDate(step.startBy))" : trailing]
        if let move { parts.append("moved \(move.to < move.from ? "earlier" : "later"), was \(formatDate(move.from))") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        if let onPress {
            Button(action: onPress) { row }
                .buttonStyle(PressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel)
                .accessibilityAddTraits(.isButton)
        } else {
            row.accessibilityElement(children: .ignore).accessibilityLabel(spokenLabel)
        }
    }

    private var row: some View {
        HStack(spacing: Space.sm) {
            Text(mark).font(TypeStyle.body).foregroundStyle(markColor).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(TypeStyle.label)
                    .foregroundStyle(step.status == .done || step.status == .skipped ? p.dim : p.text)
                    .strikethrough(step.status == .skipped)
                    .lineLimit(detailed ? 2 : 1)
                if detailed && open {
                    Text(detailLine).font(TypeStyle.caption).foregroundStyle(overdue ? p.late : p.dim)
                }
                if let subtitle { Text(subtitle).font(TypeStyle.caption).foregroundStyle(p.dim).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !detailed || !open {
                Text(trailing).font(TypeStyle.caption).foregroundStyle(overdue ? p.late : p.dim)
                    .lineLimit(1).frame(maxWidth: 120, alignment: .trailing).fixedSize(horizontal: true, vertical: false)
            }
            if let move {
                InfoPopover(text: "Now \(formatDate(move.to)). Moved because: \(move.cause).",
                            title: "Was \(formatDate(move.from))",
                            label: "Moved \(move.to < move.from ? "earlier" : "later"), why") {
                    Text(move.to < move.from ? "▲" : "▼").font(TypeStyle.caption).foregroundStyle(p.accent)
                }
            }
            Text("›").font(TypeStyle.body).foregroundStyle(p.faint)
        }
        .padding(.vertical, Space.md).padding(.horizontal, Space.lg)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}
