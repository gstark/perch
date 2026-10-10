import Foundation
import SQLite3

/// Writes and reads a store's file directly, for fixtures the capture path cannot backdate.
enum ClipboardSeed {
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Oldest first, so the newest row gets the highest rowid, as live captures do. Reload after.
    static func insert(_ items: [ClipboardItem], into directory: URL) {
        withDatabase(in: directory) { db in
            var stmt: OpaquePointer?
            let sql = """
                INSERT INTO items(id, kind, text, image_path, created_at, source_app, pinned_at)
                VALUES(?,?,?,?,?,?,?)
                """
            precondition(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
            defer { sqlite3_finalize(stmt) }
            sqlite3_exec(db, "BEGIN", nil, nil, nil)
            for item in items.sorted(by: { $0.createdAt < $1.createdAt }) {
                bind(stmt, 1, item.id.uuidString)
                bind(stmt, 2, item.kind.rawValue)
                bind(stmt, 3, item.text)
                bind(stmt, 4, item.imagePath)
                sqlite3_bind_double(stmt, 5, item.createdAt.timeIntervalSince1970)
                bind(stmt, 6, item.sourceBundleID)
                if let pinnedAt = item.pinnedAt {
                    sqlite3_bind_double(stmt, 7, pinnedAt.timeIntervalSince1970)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }
                precondition(sqlite3_step(stmt) == SQLITE_DONE)
                sqlite3_reset(stmt)
            }
            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    /// Every row in insertion order, past the memory window `items` stops at.
    static func all(in directory: URL) -> [ClipboardItem] {
        var items: [ClipboardItem] = []
        withDatabase(in: directory) { db in
            var stmt: OpaquePointer?
            let sql = """
                SELECT id, kind, text, image_path, created_at, source_app, pinned_at
                FROM items ORDER BY rowid
                """
            precondition(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let id = string(stmt, 0).flatMap(UUID.init(uuidString:)),
                    let kind = string(stmt, 1).flatMap(ClipboardItem.Kind.init(rawValue:))
                else { continue }
                let pinned = sqlite3_column_type(stmt, 6) == SQLITE_NULL
                    ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
                items.append(
                    ClipboardItem(
                        id: id, kind: kind, text: string(stmt, 2), imagePath: string(stmt, 3),
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                        sourceBundleID: string(stmt, 5), pinnedAt: pinned))
            }
        }
        return items
    }

    private static func withDatabase(in directory: URL, _ body: (OpaquePointer) -> Void) {
        var db: OpaquePointer?
        let url = directory.appendingPathComponent("clipboard.sqlite3")
        precondition(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        defer { sqlite3_close_v2(db) }
        sqlite3_busy_timeout(db, 5_000)
        body(db!)
    }

    private static func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, transient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private static func string(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        return String(decoding: UnsafeBufferPointer(start: text, count: count), as: UTF8.self)
    }
}
