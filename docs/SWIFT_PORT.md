# Swift port

Native SwiftUI rewrite of the React Native app, same bundle ID (upgrades in place, keeps data).
The TypeScript in `src/` is the spec; port behaviour, not syntax. Delete nothing in `src/`/`ios/` until the Swift app ships.

```
Core/                     Swift package PaperWorksCore — pure Foundation, `swift test` on macOS
  Sources/PaperWorksCore/
    Types.swift           shared Codable types (src/domain/types.ts) — the contract, extend don't rename
    Resources/            playbooks.json, kinds.json, regions.json, names-en/zh.json (exported from src/content)
  Tests/PaperWorksCoreTests/   ported from __tests__/
App/                      the iOS app (xcodegen: project.yml → PaperWorksSwift.xcodeproj)
  App/        entry, AppModel (src/state/store.ts)
  Data/       SQLite persistence (reads the RN db: Library/paper-works.db, tables (id, json)), backups
  Platform/   notifications, calendar, reminders export, iCloud backup, files, haptics (ios/PaperWorks/Native/*.swift minus the RN bridge)
  UI/         theme + shared views (src/ui)
  Screens/    one file per screen (src/screens), drawings in docs/uiux
```

Rules
- Core stays pure: no UIKit/SwiftUI/SQLite. Dates are `CivilDate` strings, never `Date` in a type.
- Match TS names in Swift style (`timelineNodes` stays `timelineNodes`), `public` for anything the app uses.
- Each agent owns only its files; don't edit another agent's files — note the need in your report.
- Core: `cd Core && swift test`. App: `xcodegen generate && xcodebuild -project PaperWorksSwift.xcodeproj -scheme PaperWorks -destination 'generic/platform=iOS' -derivedDataPath /tmp/pw-swift-<you> CODE_SIGNING_ALLOWED=NO build`.
- Never use a simulator or Metro.
