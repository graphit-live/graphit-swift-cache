import Foundation
import SQLite3

internal final class SQLiteConnection {
    private let database: OpaquePointer

    init(url: URL) throws {
        var openedDatabase: OpaquePointer?
        let status = sqlite3_open_v2(
            url.path,
            &openedDatabase,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        )

        guard status == SQLITE_OK, let openedDatabase else {
            let message: String
            if let openedDatabase {
                message = String(cString: sqlite3_errmsg(openedDatabase))
                sqlite3_close(openedDatabase)
            } else {
                message = "sqlite3_open_v2 returned status \(status)."
            }
            throw CacheError.storageFailure("Failed to open SQLite metadata index: \(message)")
        }

        self.database = openedDatabase
    }

    deinit {
        sqlite3_close(database)
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard status == SQLITE_OK else {
            let message: String
            if let errorMessage {
                message = String(cString: errorMessage)
                sqlite3_free(errorMessage)
            } else {
                message = lastErrorMessage()
            }
            throw CacheError.storageFailure("SQLite execution failed: \(message)")
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            throw CacheError.storageFailure("SQLite prepare failed: \(lastErrorMessage())")
        }
        return SQLiteStatement(statement: statement, connection: self)
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let value = try body()
            try execute("COMMIT;")
            return value
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(database))
    }
}
