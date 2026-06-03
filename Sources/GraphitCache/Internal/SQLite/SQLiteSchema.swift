import Foundation

internal enum SQLiteSchema {
    static func apply(to connection: SQLiteConnection) throws {
        try connection.execute("PRAGMA foreign_keys = ON;")
        try connection.execute("PRAGMA journal_mode = WAL;")
        try connection.execute("PRAGMA synchronous = NORMAL;")

        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS entries (
                id TEXT PRIMARY KEY,
                bucket TEXT NOT NULL,
                key TEXT NOT NULL,
                payload_kind TEXT NOT NULL,
                storage_ref TEXT NOT NULL,
                size_bytes INTEGER NOT NULL,
                stored_at_us INTEGER NOT NULL,
                last_accessed_at_us INTEGER,
                expires_at_us INTEGER,
                expiration_kind TEXT NOT NULL,
                expiration_duration_us INTEGER,
                UNIQUE(bucket, key)
            );
            """
        )

        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS tags (
                entry_id TEXT NOT NULL,
                tag TEXT NOT NULL,
                PRIMARY KEY (entry_id, tag),
                FOREIGN KEY (entry_id) REFERENCES entries(id) ON DELETE CASCADE
            );
            """
        )

        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_entries_bucket_stored_at
            ON entries(bucket, stored_at_us);
            """
        )

        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_entries_bucket_lru
            ON entries(bucket, last_accessed_at_us, stored_at_us);
            """
        )

        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_entries_expires_at
            ON entries(expires_at_us);
            """
        )

        try connection.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_tags_tag_entry
            ON tags(tag, entry_id);
            """
        )

        let currentVersion = try userVersion(connection)
        if currentVersion < 1 {
            try connection.execute("PRAGMA user_version = 1;")
        }
    }

    private static func userVersion(_ connection: SQLiteConnection) throws -> Int64 {
        let statement = try connection.prepare("PRAGMA user_version;")
        guard try statement.step() else {
            throw CacheError.storageFailure("SQLite did not return a schema user_version.")
        }
        return statement.columnInt64(at: 0)
    }
}
