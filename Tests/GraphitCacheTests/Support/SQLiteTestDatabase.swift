import Foundation
import SQLite3

final class SQLiteTestDatabase {
    private let database: OpaquePointer

    init(url: URL) throws {
        var opened: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_READWRITE, nil)
        guard status == SQLITE_OK, let opened else {
            if let opened {
                sqlite3_close(opened)
            }
            throw TestDatabaseError.openFailed(status)
        }
        self.database = opened
    }

    deinit {
        sqlite3_close(database)
    }

    func strings(_ sql: String) throws -> [String] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                values.append(String(cString: UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self)))
            }
        }
        return values
    }

    func int(_ sql: String) throws -> Int64 {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw TestDatabaseError.queryReturnedNoRows
        }
        return sqlite3_column_int64(statement, 0)
    }

    func storageRef(bucket: String, key: String) throws -> String? {
        let statement = try prepare("SELECT storage_ref FROM entries WHERE bucket = ? AND key = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }
        try bind(bucket, to: statement, at: 1)
        try bind(key, to: statement, at: 2)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        guard let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self))
    }

    func updateStorageRef(_ storageRef: String, bucket: String, key: String) throws {
        let statement = try prepare("UPDATE entries SET storage_ref = ? WHERE bucket = ? AND key = ?;")
        defer { sqlite3_finalize(statement) }
        try bind(storageRef, to: statement, at: 1)
        try bind(bucket, to: statement, at: 2)
        try bind(key, to: statement, at: 3)

        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE else {
            throw TestDatabaseError.stepFailed(status)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            throw TestDatabaseError.prepareFailed(status)
        }
        return statement
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        let status = value.withCString { cString in
            sqlite3_bind_text(statement, index, cString, -1, sqliteTransient)
        }
        guard status == SQLITE_OK else {
            throw TestDatabaseError.bindFailed(status)
        }
    }
}

enum TestDatabaseError: Error {
    case openFailed(Int32)
    case prepareFailed(Int32)
    case bindFailed(Int32)
    case stepFailed(Int32)
    case queryReturnedNoRows
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
