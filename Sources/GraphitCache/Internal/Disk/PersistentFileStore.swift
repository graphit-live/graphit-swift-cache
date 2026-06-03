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

internal struct OrphanFileRemovalResult: Sendable {
    let removedFiles: Int
    let removedBytes: ByteCount

    static let empty = OrphanFileRemovalResult(removedFiles: 0, removedBytes: .zero)
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

    func storageRefExists(_ storageRef: String) -> Bool {
        guard let url = try? url(forStorageRef: storageRef) else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func removeStorageRefs(_ storageRefs: [String]) throws {
        for storageRef in storageRefs {
            guard let url = try? url(forStorageRef: storageRef) else {
                continue
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw CacheError.storageFailure("Failed to remove cache payload at \(url.path): \(error.localizedDescription)")
            }
        }
    }

    func removeTemporaryOrphans(excluding activeTemporaryFiles: Set<URL> = []) throws -> OrphanFileRemovalResult {
        let urls = try directoryContents(at: temporaryDirectory).filter { url in
            !activeTemporaryFiles.contains(url)
        }
        return try removeOrphanFiles(urls)
    }

    func removeFinalOrphans(
        knownStorageRefs: Set<String>,
        in bucket: CacheBucketID? = nil
    ) throws -> OrphanFileRemovalResult {
        let scanRoot = if let bucket {
            bucketsDirectory.appendingPathComponent(bucket.rawValue, isDirectory: true)
        } else {
            bucketsDirectory
        }

        guard FileManager.default.fileExists(atPath: scanRoot.path) else {
            return .empty
        }

        let payloadURLs = try recursiveRegularFiles(at: scanRoot)
        let orphanURLs = payloadURLs.filter { url in
            guard let storageRef = storageRef(forPayloadURL: url) else {
                return false
            }
            return !knownStorageRefs.contains(storageRef)
        }
        return try removeOrphanFiles(orphanURLs)
    }

    func moveTemporaryFile(from temporaryURL: URL, to storageRef: String) throws {
        let destinationURL = try url(forStorageRef: storageRef)
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
            guard let url = try? url(forStorageRef: storageRef) else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func url(forStorageRef storageRef: String) throws -> URL {
        try validatedStorageRefComponents(storageRef).reduce(rootDirectory) { url, component in
            url.appendingPathComponent(component, isDirectory: false)
        }
    }

    private func directoryContents(at url: URL) throws -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw CacheError.storageFailure("Failed to scan cache directory at \(url.path): \(error.localizedDescription)")
        }
    }

    private func recursiveRegularFiles(at url: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CacheError.storageFailure("Failed to scan cache directory at \(url.path).")
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let values: URLResourceValues
            do {
                values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            } catch {
                throw CacheError.storageFailure("Failed to inspect cache file at \(fileURL.path): \(error.localizedDescription)")
            }
            if values.isRegularFile == true {
                files.append(fileURL)
            }
        }
        return files
    }

    private func removeOrphanFiles(_ urls: [URL]) throws -> OrphanFileRemovalResult {
        guard !urls.isEmpty else {
            return .empty
        }

        var removedFiles = 0
        var removedBytes: Int64 = 0
        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            removedBytes += try byteCountForRegularFile(at: url)
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw CacheError.storageFailure("Failed to remove orphaned cache file at \(url.path): \(error.localizedDescription)")
            }
            removedFiles += 1
        }

        return OrphanFileRemovalResult(
            removedFiles: removedFiles,
            removedBytes: ByteCount.bytes(removedBytes)
        )
    }

    private func byteCountForRegularFile(at url: URL) throws -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                return 0
            }
            return Int64(values.fileSize ?? 0)
        } catch {
            throw CacheError.storageFailure("Failed to read cache file size at \(url.path): \(error.localizedDescription)")
        }
    }

    private func storageRef(forPayloadURL url: URL) -> String? {
        let bucketsPath = bucketsDirectory.resolvingSymlinksInPath().path
        let prefix = bucketsPath.hasSuffix("/") ? bucketsPath : bucketsPath + "/"
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(prefix) else {
            return nil
        }
        let bucketRelativePath = String(path.dropFirst(prefix.count))
        guard !bucketRelativePath.isEmpty else {
            return nil
        }
        return "buckets/" + bucketRelativePath
    }

    private func validatedStorageRefComponents(_ storageRef: String) throws -> [String] {
        guard !storageRef.isEmpty else {
            throw invalidStorageRef(storageRef)
        }
        guard !storageRef.contains("\\") else {
            throw invalidStorageRef(storageRef)
        }
        guard !storageRef.unicodeScalars.contains(where: { scalar in
            scalar.value <= 0x1F || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value)
        }) else {
            throw invalidStorageRef(storageRef)
        }

        let components = storageRef.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 5, components[0] == "buckets" else {
            throw invalidStorageRef(storageRef)
        }
        guard components.allSatisfy({ component in
            !component.isEmpty && component != "." && component != ".."
        }) else {
            throw invalidStorageRef(storageRef)
        }

        do {
            try CacheValidation.validateBucketIDForInput(CacheBucketID(components[1]))
        } catch {
            throw invalidStorageRef(storageRef)
        }

        return components
    }

    private func invalidStorageRef(_ storageRef: String) -> CacheError {
        CacheError.internalInconsistency("Invalid cache storage reference in metadata: \(storageRef)")
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
        try data.write(to: temporaryURL)
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
