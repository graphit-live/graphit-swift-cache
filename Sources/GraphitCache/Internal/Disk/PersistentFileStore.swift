import Foundation

internal struct PayloadWritePlan: Sendable {
    let entryID: String
    let writeID: String
    let temporaryURL: URL
    let storageRef: String
}

internal struct SourceFileMetadata: Sendable {
    let size: ByteCount
}

internal struct PersistentFileStore: Sendable {
    let rootDirectory: URL
    let indexDirectory: URL
    let bucketsDirectory: URL
    let temporaryDirectory: URL
    let metadataDatabaseURL: URL

    init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        self.indexDirectory = rootDirectory.appendingPathComponent("index", isDirectory: true)
        self.bucketsDirectory = rootDirectory.appendingPathComponent("buckets", isDirectory: true)
        self.temporaryDirectory = rootDirectory.appendingPathComponent("tmp", isDirectory: true)
        self.metadataDatabaseURL = indexDirectory.appendingPathComponent("metadata.sqlite", isDirectory: false)

        try createDirectory(rootDirectory)
        try createDirectory(indexDirectory)
        try createDirectory(bucketsDirectory)
        try createDirectory(temporaryDirectory)
    }

    func planDataWrite(bucket: CacheBucketID, key: CacheKey) -> PayloadWritePlan {
        planWrite(bucket: bucket, key: key, fileExtension: "bin")
    }

    func planFileWrite(bucket: CacheBucketID, key: CacheKey, fileExtension: String) -> PayloadWritePlan {
        planWrite(bucket: bucket, key: key, fileExtension: fileExtension)
    }

    func validateSourceFile(at sourceURL: URL) throws -> SourceFileMetadata {
        guard sourceURL.isFileURL else {
            throw CacheError.invalidInput("Source file URL must be a file URL.")
        }

        let path = sourceURL.path
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw CacheError.sourceFileNotFound(sourceURL)
        }
        guard !isDirectory.boolValue else {
            throw CacheError.sourceFileUnreadable(sourceURL)
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw CacheError.sourceFileUnreadable(sourceURL)
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            if let fileType = attributes[.type] as? FileAttributeType, fileType != .typeRegular {
                throw CacheError.sourceFileUnreadable(sourceURL)
            }
            guard let sizeValue = attributes[.size] as? NSNumber else {
                throw CacheError.storageFailure("Source file size is unavailable for \(sourceURL.path).")
            }
            let size = sizeValue.int64Value
            guard size >= 0 else {
                throw CacheError.storageFailure("Source file size is invalid for \(sourceURL.path).")
            }
            return SourceFileMetadata(size: ByteCount.bytes(size))
        } catch let error as CacheError {
            throw error
        } catch {
            throw CacheError.sourceFileUnreadable(sourceURL)
        }
    }

    func writeDataToTemporaryFile(_ data: Data, at temporaryURL: URL) async throws {
        try await writeCacheDataToTemporaryFile(data, at: temporaryURL)
    }

    func copySourceFileToTemporaryFile(from sourceURL: URL, to temporaryURL: URL) async throws {
        try await copyCacheSourceFileToTemporaryFile(from: sourceURL, to: temporaryURL)
    }

    func fileSize(at url: URL) throws -> ByteCount {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let sizeValue = attributes[.size] as? NSNumber else {
                throw CacheError.storageFailure("File size is unavailable for \(url.path).")
            }
            let size = sizeValue.int64Value
            guard size >= 0 else {
                throw CacheError.storageFailure("File size is invalid for \(url.path).")
            }
            return ByteCount.bytes(size)
        } catch let error as CacheError {
            throw error
        } catch {
            throw CacheError.storageFailure("Failed to read file attributes at \(url.path): \(error.localizedDescription)")
        }
    }

    func readData(storageRef: String) async throws -> Data {
        try await readCacheDataFile(at: url(forStorageRef: storageRef))
    }

    func moveTemporaryFile(from temporaryURL: URL, to storageRef: String) throws {
        let destinationURL = url(forStorageRef: storageRef)
        try createDirectory(destinationURL.deletingLastPathComponent())
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            throw CacheError.storageFailure("Failed to move cache payload into place: \(error.localizedDescription)")
        }
    }

    func removeTemporaryFileBestEffort(at temporaryURL: URL) {
        try? FileManager.default.removeItem(at: temporaryURL)
    }

    func removeStorageRefsBestEffort(_ storageRefs: [String]) {
        for storageRef in storageRefs {
            try? FileManager.default.removeItem(at: url(forStorageRef: storageRef))
        }
    }

    func url(forStorageRef storageRef: String) -> URL {
        storageRef.split(separator: "/").reduce(rootDirectory) { url, component in
            url.appendingPathComponent(String(component), isDirectory: false)
        }
    }

    private func planWrite(bucket: CacheBucketID, key: CacheKey, fileExtension: String) -> PayloadWritePlan {
        let entryID = StableKeyHasher.entryID(bucket: bucket, key: key)
        let writeID = UUID().uuidString.lowercased()
        let firstShard = String(entryID.prefix(2))
        let secondShardStart = entryID.index(entryID.startIndex, offsetBy: 2)
        let secondShardEnd = entryID.index(secondShardStart, offsetBy: 2)
        let secondShard = String(entryID[secondShardStart..<secondShardEnd])
        let storageRef = [
            "buckets",
            bucket.rawValue,
            firstShard,
            secondShard,
            "\(entryID)-\(writeID).\(fileExtension)"
        ].joined(separator: "/")
        let temporaryURL = temporaryDirectory
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: false)
            .appendingPathExtension("tmp")

        return PayloadWritePlan(
            entryID: entryID,
            writeID: writeID,
            temporaryURL: temporaryURL,
            storageRef: storageRef
        )
    }

    private func createDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            excludeFromBackupBestEffort(url)
        } catch {
            throw CacheError.storageFailure("Failed to create cache directory at \(url.path): \(error.localizedDescription)")
        }
    }

    private func excludeFromBackupBestEffort(_ url: URL) {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(values)
    }
}

@concurrent
private func writeCacheDataToTemporaryFile(_ data: Data, at temporaryURL: URL) async throws {
    do {
        try data.write(to: temporaryURL, options: [.atomic])
    } catch {
        throw CacheError.storageFailure("Failed to write cache data to a temporary file: \(error.localizedDescription)")
    }
}

@concurrent
private func copyCacheSourceFileToTemporaryFile(from sourceURL: URL, to temporaryURL: URL) async throws {
    do {
        try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
    } catch {
        throw CacheError.storageFailure("Failed to copy source file into cache storage: \(error.localizedDescription)")
    }
}

@concurrent
private func readCacheDataFile(at url: URL) async throws -> Data {
    do {
        return try Data(contentsOf: url)
    } catch {
        throw CacheError.storageFailure("Failed to read cache payload at \(url.path): \(error.localizedDescription)")
    }
}
