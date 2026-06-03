import Foundation
import SQLite3

internal final class SQLiteStatement {
    private let statement: OpaquePointer
    private let connection: SQLiteConnection

    init(statement: OpaquePointer, connection: SQLiteConnection) {
        self.statement = statement
        self.connection = connection
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bindText(_ value: String, at index: Int32) throws {
        // SQLite copies the bytes before `withCString` returns because SQLITE_TRANSIENT is used.
        let status = value.withCString { cString in
            sqlite3_bind_text(statement, index, cString, -1, sqliteTransient)
        }
        try validateBind(status)
    }

    func bindInt64(_ value: Int64, at index: Int32) throws {
        try validateBind(sqlite3_bind_int64(statement, index, value))
    }

    func bindNull(at index: Int32) throws {
        try validateBind(sqlite3_bind_null(statement, index))
    }

    func bindOptionalInt64(_ value: Int64?, at index: Int32) throws {
        if let value {
            try bindInt64(value, at: index)
        } else {
            try bindNull(at: index)
        }
    }

    func step() throws -> Bool {
        let status = sqlite3_step(statement)
        switch status {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw CacheError.storageFailure("SQLite step failed: \(connection.lastErrorMessage())")
        }
    }

    func run() throws {
        while try step() {}
    }

    func columnText(at index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self))
    }

    func columnInt64(at index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    func columnIsNull(at index: Int32) -> Bool {
        sqlite3_column_type(statement, index) == SQLITE_NULL
    }

    private func validateBind(_ status: Int32) throws {
        guard status == SQLITE_OK else {
            throw CacheError.storageFailure("SQLite bind failed: \(connection.lastErrorMessage())")
        }
    }
}

/// SQLite's C API accepts this sentinel to copy bound text bytes immediately.
/// The unsafe cast is contained here so call sites can bind Swift strings safely.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
