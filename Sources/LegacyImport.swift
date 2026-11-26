import Foundation
import SQLite3

/// Import układu z bazy starego Launchpada (macOS ≤ 15), jeśli przetrwała aktualizację.
/// Baza: $(getconf DARWIN_USER_DIR)/com.apple.dock.launchpad/db/db
/// Tabele: items(rowid, type, parent_id, ordering), apps(item_id, bundleid), groups(item_id, title)
/// Typy: 2 = folder, 3 = strona, 4 = aplikacja.
enum LegacyLaunchpad {
    static var databaseURL: URL? {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let n = confstr(_CS_DARWIN_USER_DIR, &buf, buf.count)
        guard n > 0 else { return nil }
        let dir = String(cString: buf)
        let url = URL(fileURLWithPath: dir).appendingPathComponent("com.apple.dock.launchpad/db/db")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private struct Row {
        let id: Int64
        let type: Int64
        let parent: Int64
        let ordering: Int64
    }

    static func importLayout(bundleMap: [String: String]) -> [[Item]]? {
        guard let source = databaseURL else { return nil }
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("lp-import-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let copy = tmp.appendingPathComponent("db")
        for suffix in ["", "-wal", "-shm"] {
            let s = URL(fileURLWithPath: source.path + suffix)
            if fm.fileExists(atPath: s.path) {
                try? fm.copyItem(at: s, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return nil }
        defer { sqlite3_close(db) }

        func query(_ sql: String, _ row: (OpaquePointer) -> Void) {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
        }

        func text(_ stmt: OpaquePointer, _ col: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, col) else { return nil }
            return String(cString: c)
        }

        var rows: [Row] = []
        query("SELECT rowid, type, parent_id, ordering FROM items") { s in
            rows.append(Row(id: sqlite3_column_int64(s, 0), type: sqlite3_column_int64(s, 1),
                            parent: sqlite3_column_int64(s, 2), ordering: sqlite3_column_int64(s, 3)))
        }
        guard !rows.isEmpty else { return nil }

        var bundles: [Int64: String] = [:]
        query("SELECT item_id, bundleid FROM apps") { s in
            if let b = text(s, 1) { bundles[sqlite3_column_int64(s, 0)] = b }
        }
        var titles: [Int64: String] = [:]
        query("SELECT item_id, title FROM groups") { s in
            if let t = text(s, 1) { titles[sqlite3_column_int64(s, 0)] = t }
        }

        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var children: [Int64: [Row]] = [:]
        for r in rows { children[r.parent, default: []].append(r) }
        for key in Array(children.keys) { children[key]?.sort { $0.ordering < $1.ordering } }

        let rootPages = rows
            .filter { $0.type == 3 && byID[$0.parent]?.type != 2 }
            .sorted { ($0.parent, $0.ordering) < ($1.parent, $1.ordering) }

        var used = Set<String>()
        func appID(_ r: Row) -> String? {
            guard let b = bundles[r.id], let id = bundleMap[b], used.insert(id).inserted else { return nil }
            return id
        }

        var pages: [[Item]] = []
        for page in rootPages {
            var items: [Item] = []
            for child in children[page.id] ?? [] {
                if child.type == 4, let id = appID(child) {
                    items.append(.app(id))
                } else if child.type == 2 {
                    var folderApps: [String] = []
                    for fp in children[child.id] ?? [] where fp.type == 3 {
                        for a in children[fp.id] ?? [] where a.type == 4 {
                            if let id = appID(a) { folderApps.append(id) }
                        }
                    }
                    if folderApps.count == 1 {
                        items.append(.app(folderApps[0]))
                    } else if folderApps.count > 1 {
                        let name = titles[child.id].flatMap { $0.isEmpty ? nil : $0 } ?? "Folder"
                        items.append(.folder(Folder(id: UUID().uuidString, name: name, apps: folderApps)))
                    }
                }
            }
            if !items.isEmpty { pages.append(items) }
        }
        return pages.isEmpty ? nil : pages
    }
}
