import Foundation
import PaperWorksCore
import SQLite3

private let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DatabaseError: Error { case open(String), sql(String) }

/// Thin wrapper over one SQLite connection.
final class SQLiteConnection {
    private var db: OpaquePointer?

    init(url: URL) throws {
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            throw DatabaseError.open(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_busy_timeout(db, 3000)
    }

    deinit { sqlite3_close(db) }

    @discardableResult
    func run(_ sql: String, _ args: [String] = []) throws -> [[String: String]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.sql(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        for (i, a) in args.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), a, -1, TRANSIENT) }
        var rows: [[String: String]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw DatabaseError.sql(String(cString: sqlite3_errmsg(db))) }
            var row: [String: String] = [:]
            for c in 0..<sqlite3_column_count(stmt) {
                if let t = sqlite3_column_text(stmt, c) { row[String(cString: sqlite3_column_name(stmt, c))] = String(cString: t) }
            }
            rows.append(row)
        }
        return rows
    }

    func transaction(_ body: () throws -> Void) throws {
        try run("BEGIN")
        do { try body(); try run("COMMIT") } catch { _ = try? run("ROLLBACK"); throw error }
    }
}

/// Where op-sqlite put the React Native app's databases: Library first, then Documents. New files go in Library.
func databaseURL(_ name: String) -> URL {
    let fm = FileManager.default
    let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let candidates = [library, documents].map { $0.appendingPathComponent(name) }
    return candidates.first { fm.fileExists(atPath: $0.path) } ?? candidates[0]
}

private let TABLES = ["people", "anchors", "playbooks", "tracks", "instances", "documents"]

private let MIGRATIONS: [[String]] = [
    ["anchors", "playbooks", "tracks", "instances", "documents"].map {
        "CREATE TABLE IF NOT EXISTS \($0) (id TEXT PRIMARY KEY, json TEXT NOT NULL)"
    } + ["CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, json TEXT NOT NULL)"],
    ["CREATE TABLE IF NOT EXISTS entries (id TEXT PRIMARY KEY, json TEXT NOT NULL)"],
    ["DROP TABLE IF EXISTS entries"],
    ["CREATE TABLE IF NOT EXISTS people (id TEXT PRIMARY KEY, json TEXT NOT NULL)"],
]

/// One row per entity, JSON body; writes only what changed since the last load/save.
@MainActor
final class Repository {
    private let name: String
    private var conn: SQLiteConnection?
    private var written: [String: String] = [:]

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    init(name: String = "paper-works.db") { self.name = name }

    private func connection() throws -> SQLiteConnection {
        if let conn { return conn }
        let c = try SQLiteConnection(url: databaseURL(name))
        try c.run("CREATE TABLE IF NOT EXISTS migrations (version INTEGER PRIMARY KEY, applied_on TEXT NOT NULL)")
        let current = Int(try c.run("SELECT MAX(version) AS v FROM migrations").first?["v"] ?? "0") ?? 0
        if current < MIGRATIONS.count {
            for v in (current + 1)...MIGRATIONS.count {
                try c.transaction {
                    for sql in MIGRATIONS[v - 1] { try c.run(sql) }
                    try c.run("INSERT INTO migrations (version, applied_on) VALUES (?, ?)",
                              [String(v), ISO8601DateFormatter().string(from: Date())])
                }
            }
        }
        conn = c
        return c
    }

    func load() throws -> Stored? {
        let c = try connection()
        written = [:]
        var out = Stored()
        out.people = []
        var any = false
        let decoder = JSONDecoder()

        func rows<T: Decodable>(_ table: String, _: T.Type) throws -> [T] {
            let found = try c.run("SELECT id, json FROM \(table)")
            if !found.isEmpty { any = true }
            return found.compactMap { r in
                guard let json = r["json"], let id = r["id"],
                      let v = try? decoder.decode(T.self, from: Data(json.utf8)) else { return nil }
                written["\(table):\(id)"] = json
                return v
            }
        }
        out.people = try rows("people", Person.self)
        out.anchors = try rows("anchors", Anchor.self)
        out.playbooks = try rows("playbooks", Playbook.self)
        out.tracks = try rows("tracks", Track.self)
        out.instances = try rows("instances", StepInstance.self)
        out.documents = try rows("documents", DocumentRecord.self)

        for r in try c.run("SELECT key, json FROM meta") {
            guard let key = r["key"], let json = r["json"] else { continue }
            any = true
            let data = Data(json.utf8)
            if key == "settings", let s = try? decoder.decode(Settings.self, from: data) {
                out.settings = s
                written["meta:settings"] = json
            }
            if key == "moves", let m = try? decoder.decode(Moves.self, from: data) {
                out.moves = m
                written["meta:moves"] = json
            }
        }
        return any ? out : nil
    }

    func save(_ state: Stored) throws {
        let c = try connection()
        var next: [String: String] = [:]
        func put<T: Encodable>(_ table: String, _ items: [T], id: (T) -> String) throws {
            for item in items { next["\(table):\(id(item))"] = String(decoding: try Self.encoder.encode(item), as: UTF8.self) }
        }
        try put("people", state.people) { $0.id }
        try put("anchors", state.anchors) { $0.id }
        try put("playbooks", state.playbooks) { $0.id }
        try put("tracks", state.tracks) { $0.id }
        try put("instances", state.instances) { $0.id }
        try put("documents", state.documents) { $0.id }
        next["meta:settings"] = String(decoding: try Self.encoder.encode(state.settings), as: UTF8.self)
        next["meta:moves"] = String(decoding: try Self.encoder.encode(state.moves), as: UTF8.self)

        let upserts = next.filter { written[$0.key] != $0.value }
        let deletes = written.keys.filter { next[$0] == nil }
        if upserts.isEmpty && deletes.isEmpty { return }

        func split(_ key: String) -> (table: String, id: String) {
            let i = key.firstIndex(of: ":")!
            return (String(key[..<i]), String(key[key.index(after: i)...]))
        }
        try c.transaction {
            for (key, json) in upserts {
                let (table, id) = split(key)
                try c.run("INSERT OR REPLACE INTO \(table) (\(table == "meta" ? "key" : "id"), json) VALUES (?, ?)", [id, json])
            }
            for key in deletes {
                let (table, id) = split(key)
                try c.run("DELETE FROM \(table) WHERE \(table == "meta" ? "key" : "id") = ?", [id])
            }
        }
        for (k, v) in upserts { written[k] = v }
        for k in deletes { written[k] = nil }
    }
}

/// Switches kept outside every plan, e.g. which store the app opens on (flags.db).
@MainActor
final class Flags {
    private var conn: SQLiteConnection?
    private let name: String

    init(name: String = "flags.db") { self.name = name }

    private func connection() throws -> SQLiteConnection {
        if let conn { return conn }
        let c = try SQLiteConnection(url: databaseURL(name))
        try c.run("CREATE TABLE IF NOT EXISTS flags (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        conn = c
        return c
    }

    func get(_ key: String) -> String? {
        try? connection().run("SELECT value FROM flags WHERE key = ?", [key]).first?["value"]
    }

    func set(_ key: String, _ value: String) throws {
        try connection().run("INSERT OR REPLACE INTO flags (key, value) VALUES (?, ?)", [key, value])
    }
}
