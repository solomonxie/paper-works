import SwiftUI

/// One stack, TimelineScreen at the root; anchorEdit and person present as sheets (src/navigation/RootNavigator.tsx).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var p

    private static func isModal(_ r: Route) -> Bool {
        switch r { case .anchorEdit, .person: true; default: false }
    }

    private var modal: Route? { model.path.last.flatMap { Self.isModal($0) ? $0 : nil } }

    private var stackPath: Binding<[Route]> {
        Binding {
            modal == nil ? model.path : Array(model.path.dropLast())
        } set: { new in
            model.path = new + (modal.map { [$0] } ?? [])
        }
    }

    private var sheet: Binding<Route?> {
        Binding {
            modal
        } set: { new in
            if new == nil, modal != nil { model.path.removeLast() }
        }
    }

    private var needsFirstRun: Bool {
        model.ready && !model.settings.firstRunDone && model.plan.anchors.isEmpty
    }

    var body: some View {
        Group {
            if needsFirstRun {
                FirstRunScreen()
            } else {
                NavigationStack(path: stackPath) {
                    TimelineScreen()
                        .navigationDestination(for: Route.self) { destination($0) }
                }
                .sheet(item: sheet) { route in
                    NavigationStack { destination(route) }
                }
            }
        }
        .background(p.bg.ignoresSafeArea())
        .tint(p.accent)
        .overlay(alignment: .bottom) { ToastHost() }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .timeline: TimelineScreen()
        case .chapter(let id): ChapterScreen(eventId: id)
        case .anchorEdit(let id, let kind): AnchorEditScreen(anchorId: id, kind: kind)
        case .settings: SettingsScreen()
        case .reminders: RemindersScreen()
        case .backups: BackupsScreen()
        case .sources: SourcesScreen()
        case .about: AboutScreen()
        case .person(let mode, let id): PersonScreen(mode: mode, personId: id)
        case .library: LibraryScreen()
        case .playbook(let id, let track): PlaybookScreen(playbookId: id, trackId: track)
        case .document(let id): DocumentScreen(documentId: id)
        case .step(let id): StepScreen(instanceId: id)
        case .firstRun: FirstRunScreen()
        case .names(let id): NamesScreen(planId: id)
        case .namesHistory(let id): NamesHistoryScreen(planId: id)
        }
    }
}

extension Route: Identifiable {
    var id: Route { self }
}

/// Bottom toast: 5 seconds, Undo while the change is undoable.
private struct ToastHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let toast = model.toast {
                ToastView(message: toast.message, onUndo: toast.undoable ? { model.undo() } : nil)
                    .id(toast.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(5))
                        if !Task.isCancelled, model.toast?.id == toast.id { model.dismissToast() }
                    }
            }
        }
        .padding(.bottom, Space.lg)
        .animation(.easeInOut(duration: 0.2), value: model.toast?.id)
    }
}
