import Foundation

actor CacheStoreEngine {
    private let configuration: CacheStoreConfiguration
    private let bucketPolicies: [CacheBucketID: BucketPolicy]
    private let diskFileStore: PersistentFileStore?
    private let metadataIndex: SQLiteMetadataIndex?
    private let leaseTable = LeaseTable()
    private var memory = MemoryCacheEngine()

    init(configuration: CacheStoreConfiguration) throws {
        self.configuration = configuration

        var bucketPolicies: [CacheBucketID: BucketPolicy] = [:]
        var hasDiskBackedBucket = false
        for bucket in configuration.buckets {
            bucketPolicies[bucket.id] = bucket.policy
            if bucket.policy.storage == .diskBacked {
                hasDiskBackedBucket = true
            }
        }
        self.bucketPolicies = bucketPolicies

        if hasDiskBackedBucket {
            guard let rootDirectory = configuration.rootDirectory else {
                throw CacheError.invalidConfiguration("Disk-backed buckets require a file URL rootDirectory.")
            }
            let fileStore = try PersistentFileStore(rootDirectory: rootDirectory)
            self.diskFileStore = fileStore
            self.metadataIndex = try SQLiteMetadataIndex(databaseURL: fileStore.metadataDatabaseURL)
        } else {
            self.diskFileStore = nil
            self.metadataIndex = nil
        }
    }

    func usage() throws -> CacheUsage {
        let bucketUsages = try configuration.buckets.map { bucket in
            try usage(bucket: bucket.id, policy: bucket.policy)
        }
        let totalBytes = bucketUsages.reduce(into: Int64(0)) { total, usage in
            total += usage.totalSize.bytes
        }
        let diskBytes = bucketUsages.reduce(into: Int64(0)) { total, usage in
            total += usage.diskSize.bytes
        }
        let memoryBytes = bucketUsages.reduce(into: Int64(0)) { total, usage in
            total += usage.memorySize.bytes
        }
        let entryCount = bucketUsages.reduce(into: 0) { total, usage in
            total += usage.entryCount
        }

        return CacheUsage(
            totalSize: ByteCount.bytes(totalBytes),
            diskSize: ByteCount.bytes(diskBytes),
            memorySize: ByteCount.bytes(memoryBytes),
            entryCount: entryCount,
            buckets: bucketUsages
        )
    }

    func usage(bucket: CacheBucketID, policy: BucketPolicy) throws -> BucketUsage {
        switch policy.storage {
        case .memoryOnly:
            return memory.usage(in: bucket)
        case .diskBacked:
            return try diskIndex().usage(in: bucket)
        }
    }

    func cleanup() throws -> CacheCleanupResult {
        let now = configuration.clock.now()
        let expired = memory.removeExpired(now: now)
        var evictedEntries = 0
        var evictedBytes: Int64 = 0

        for bucket in configuration.buckets where bucket.policy.storage == .memoryOnly {
            let eviction = memory.enforceCapacity(in: bucket.id, policy: bucket.policy)
            evictedEntries += eviction.removedEntries
            evictedBytes += eviction.removedBytes.bytes
        }

        return CacheCleanupResult(
            removedExpiredEntries: expired.removedEntries,
            removedExpiredBytes: expired.removedBytes,
            evictedEntries: evictedEntries,
            evictedBytes: ByteCount.bytes(evictedBytes)
        )
    }

    func cleanup(bucket: CacheBucketID) throws -> CacheCleanupResult {
        guard let policy = bucketPolicies[bucket], policy.storage == .memoryOnly else {
            return .empty
        }

        let now = configuration.clock.now()
        let expired = memory.removeExpired(in: bucket, now: now)
        let eviction = memory.enforceCapacity(in: bucket, policy: policy)

        return CacheCleanupResult(
            removedExpiredEntries: expired.removedEntries,
            removedExpiredBytes: expired.removedBytes,
            evictedEntries: eviction.removedEntries,
            evictedBytes: eviction.removedBytes
        )
    }

    func removeAll() throws -> CacheRemovalResult {
        var result = memory.removeAll()
        if let metadataIndex, let diskFileStore {
            let diskRemoval = try metadataIndex.removeAll(isFileLeased: diskLeaseCheck())
            diskFileStore.removeStorageRefsBestEffort(diskRemoval.1)
            result = combined(result, diskRemoval.0)
        }
        return result
    }

    func removeAll(in bucket: CacheBucketID) throws -> CacheRemovalResult {
        var result = CacheRemovalResult.empty
        if bucketPolicies[bucket]?.storage == .memoryOnly {
            result = combined(result, memory.removeAll(in: bucket))
        }
        if let metadataIndex, let diskFileStore {
            let diskRemoval = try metadataIndex.removeAll(in: bucket, isFileLeased: diskLeaseCheck())
            diskFileStore.removeStorageRefsBestEffort(diskRemoval.1)
            result = combined(result, diskRemoval.0)
        }
        return result
    }

    func removeAll(tagged tag: CacheTag) throws -> CacheRemovalResult {
        var result = memory.removeAll(tagged: tag)
        if let metadataIndex, let diskFileStore {
            let diskRemoval = try metadataIndex.removeAll(tagged: tag, isFileLeased: diskLeaseCheck())
            diskFileStore.removeStorageRefsBestEffort(diskRemoval.1)
            result = combined(result, diskRemoval.0)
        }
        return result
    }

    func removeAll(insertedBefore date: Date) throws -> CacheRemovalResult {
        var result = memory.removeAll(insertedBefore: date)
        if let metadataIndex, let diskFileStore {
            let diskRemoval = try metadataIndex.removeAll(insertedBefore: date, isFileLeased: diskLeaseCheck())
            diskFileStore.removeStorageRefsBestEffort(diskRemoval.1)
            result = combined(result, diskRemoval.0)
        }
        return result
    }

    func removeAll(in bucket: CacheBucketID, tagged tag: CacheTag) throws -> CacheRemovalResult {
        var result = CacheRemovalResult.empty
        if bucketPolicies[bucket]?.storage == .memoryOnly {
            result = combined(result, memory.removeAll(in: bucket, tagged: tag))
        }
        if let metadataIndex, let diskFileStore {
            let diskRemoval = try metadataIndex.removeAll(in: bucket, tagged: tag, isFileLeased: diskLeaseCheck())
            diskFileStore.removeStorageRefsBestEffort(diskRemoval.1)
            result = combined(result, diskRemoval.0)
        }
        return result
    }

    func removeAll(in bucket: CacheBucketID, insertedBefore date: Date) throws -> CacheRemovalResult {
        var result = CacheRemovalResult.empty
        if bucketPolicies[bucket]?.storage == .memoryOnly {
            result = combined(result, memory.removeAll(in: bucket, insertedBefore: date))
        }
        if let metadataIndex, let diskFileStore {
            let diskRemoval = try metadataIndex.removeAll(in: bucket, insertedBefore: date, isFileLeased: diskLeaseCheck())
            diskFileStore.removeStorageRefsBestEffort(diskRemoval.1)
            result = combined(result, diskRemoval.0)
        }
        return result
    }

    func dataInfo(bucket: CacheBucketID, key: CacheKey) throws -> CacheEntryInfo? {
        guard let policy = bucketPolicies[bucket] else {
            throw CacheError.unknownBucket(bucket)
        }

        switch policy.storage {
        case .memoryOnly:
            return memory.dataInfo(bucket: bucket, key: key, now: configuration.clock.now())
        case .diskBacked:
            return try diskDataInfo(bucket: bucket, key: key)
        }
    }

    func fileInfo(bucket: CacheBucketID, key: CacheKey, policy: BucketPolicy) throws -> CacheEntryInfo? {
        try requireFileStorage(policy)
        return try diskFileInfo(bucket: bucket, key: key)
    }

    func data(bucket: CacheBucketID, key: CacheKey) async throws -> CachedData? {
        guard let policy = bucketPolicies[bucket] else {
            throw CacheError.unknownBucket(bucket)
        }

        switch policy.storage {
        case .memoryOnly:
            return memory.data(bucket: bucket, key: key, accessedAt: configuration.clock.now())
        case .diskBacked:
            return try await diskData(bucket: bucket, key: key)
        }
    }

    func setData(_ data: Data, bucket: CacheBucketID, key: CacheKey, options: CacheEntryOptions) async throws {
        guard let policy = bucketPolicies[bucket] else {
            throw CacheError.unknownBucket(bucket)
        }

        switch policy.storage {
        case .memoryOnly:
            try memory.setData(
                data,
                bucket: bucket,
                key: key,
                policy: policy,
                tags: options.tags,
                storedAt: configuration.clock.now()
            )
        case .diskBacked:
            try await setDiskData(data, bucket: bucket, key: key, options: options, policy: policy)
        }
    }

    func leaseFile(bucket: CacheBucketID, key: CacheKey, policy: BucketPolicy) throws -> CachedFileLease? {
        try requireFileStorage(policy)
        return try diskLeaseFile(bucket: bucket, key: key)
    }

    func setFile(
        at sourceURL: URL,
        bucket: CacheBucketID,
        key: CacheKey,
        options: CacheFileOptions,
        policy: BucketPolicy
    ) async throws {
        try requireFileStorage(policy)
        try await setDiskFile(at: sourceURL, bucket: bucket, key: key, options: options, policy: policy)
    }

    func remove(bucket: CacheBucketID, key: CacheKey) throws -> CacheRemovalResult {
        guard let policy = bucketPolicies[bucket] else {
            throw CacheError.unknownBucket(bucket)
        }

        switch policy.storage {
        case .memoryOnly:
            return memory.remove(bucket: bucket, key: key)
        case .diskBacked:
            let diskRemoval = try diskIndex().removeEntry(
                bucket: bucket,
                key: key,
                isFileLeased: diskLeaseCheck()
            )
            let diskFileStore = try diskStore()
            diskFileStore.removeStorageRefsBestEffort(diskRemoval.1)
            return diskRemoval.0
        }
    }

    private func setDiskData(
        _ data: Data,
        bucket: CacheBucketID,
        key: CacheKey,
        options: CacheEntryOptions,
        policy: BucketPolicy
    ) async throws {
        let size = ByteCount.bytes(Int64(data.count))
        try validateItemSize(size, bucket: bucket, policy: policy)
        try throwIfExistingFileIsLeased(bucket: bucket, key: key)

        let diskFileStore = try diskStore()
        let metadataIndex = try diskIndex()
        let plan = diskFileStore.planDataWrite(bucket: bucket, key: key)

        try Task.checkCancellation()
        do {
            try await diskFileStore.writeDataToTemporaryFile(data, at: plan.temporaryURL)
            try Task.checkCancellation()
            try throwIfExistingFileIsLeased(bucket: bucket, key: key)

            let storedAtUS = CacheDateEncoding.microsecondsSinceEpoch(configuration.clock.now())
            let expiration = try diskExpiration(policy.expiration, storedAtUS: storedAtUS)
            let write = DiskEntryWrite(
                id: plan.entryID,
                bucket: bucket,
                key: key,
                payloadKind: .data,
                storageRef: plan.storageRef,
                size: size,
                storedAtUS: storedAtUS,
                expiresAtUS: expiration.expiresAtUS,
                expirationKind: expiration.kind,
                expirationDurationUS: expiration.durationUS,
                tags: options.tags
            )

            let commit = try metadataIndex.commitWrite(write, policy: policy, isFileLeased: diskLeaseCheck()) {
                try diskFileStore.moveTemporaryFile(from: plan.temporaryURL, to: plan.storageRef)
            }
            diskFileStore.removeStorageRefsBestEffort(commit.removableStorageRefs)
        } catch is CancellationError {
            diskFileStore.removeTemporaryFileBestEffort(at: plan.temporaryURL)
            throw CancellationError()
        } catch {
            diskFileStore.removeTemporaryFileBestEffort(at: plan.temporaryURL)
            throw error
        }
    }

    private func setDiskFile(
        at sourceURL: URL,
        bucket: CacheBucketID,
        key: CacheKey,
        options: CacheFileOptions,
        policy: BucketPolicy
    ) async throws {
        let diskFileStore = try diskStore()
        let metadataIndex = try diskIndex()
        let sourceMetadata = try diskFileStore.validateSourceFile(at: sourceURL)
        try validateItemSize(sourceMetadata.size, bucket: bucket, policy: policy)
        try throwIfExistingFileIsLeased(bucket: bucket, key: key)

        let fileExtension = try resolvedFileExtension(sourceURL: sourceURL, options: options)
        let plan = diskFileStore.planFileWrite(bucket: bucket, key: key, fileExtension: fileExtension)

        try Task.checkCancellation()
        do {
            try await diskFileStore.copySourceFileToTemporaryFile(from: sourceURL, to: plan.temporaryURL)
            try Task.checkCancellation()
            let copiedSize = try diskFileStore.fileSize(at: plan.temporaryURL)
            try validateItemSize(copiedSize, bucket: bucket, policy: policy)
            try throwIfExistingFileIsLeased(bucket: bucket, key: key)

            let storedAtUS = CacheDateEncoding.microsecondsSinceEpoch(configuration.clock.now())
            let expiration = try diskExpiration(policy.expiration, storedAtUS: storedAtUS)
            let write = DiskEntryWrite(
                id: plan.entryID,
                bucket: bucket,
                key: key,
                payloadKind: .file,
                storageRef: plan.storageRef,
                size: copiedSize,
                storedAtUS: storedAtUS,
                expiresAtUS: expiration.expiresAtUS,
                expirationKind: expiration.kind,
                expirationDurationUS: expiration.durationUS,
                tags: options.tags
            )

            let commit = try metadataIndex.commitWrite(write, policy: policy, isFileLeased: diskLeaseCheck()) {
                try diskFileStore.moveTemporaryFile(from: plan.temporaryURL, to: plan.storageRef)
            }
            diskFileStore.removeStorageRefsBestEffort(commit.removableStorageRefs)
        } catch is CancellationError {
            diskFileStore.removeTemporaryFileBestEffort(at: plan.temporaryURL)
            throw CancellationError()
        } catch {
            diskFileStore.removeTemporaryFileBestEffort(at: plan.temporaryURL)
            throw error
        }
    }

    private func diskDataInfo(bucket: CacheBucketID, key: CacheKey) throws -> CacheEntryInfo? {
        guard let record = try diskIndex().fetchEntry(bucket: bucket, key: key), record.payloadKind == .data else {
            return nil
        }

        let now = configuration.clock.now()
        if record.info().isExpired(at: now) {
            try removeDiskRecord(bucket: bucket, key: key)
            return nil
        }

        return record.info()
    }

    private func diskFileInfo(bucket: CacheBucketID, key: CacheKey) throws -> CacheEntryInfo? {
        guard let record = try diskIndex().fetchEntry(bucket: bucket, key: key), record.payloadKind == .file else {
            return nil
        }

        let now = configuration.clock.now()
        if record.info().isExpired(at: now) {
            if !isFileLeased(bucket: bucket, key: key) {
                try removeDiskRecord(bucket: bucket, key: key)
            }
            return nil
        }

        return record.info()
    }

    private func diskLeaseFile(bucket: CacheBucketID, key: CacheKey) throws -> CachedFileLease? {
        guard let record = try diskIndex().fetchEntry(bucket: bucket, key: key), record.payloadKind == .file else {
            return nil
        }

        let now = configuration.clock.now()
        if record.info().isExpired(at: now) {
            if !isFileLeased(bucket: bucket, key: key) {
                try removeDiskRecord(bucket: bucket, key: key)
            }
            return nil
        }

        let diskFileStore = try diskStore()
        let fileURL = diskFileStore.url(forStorageRef: record.storageRef)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            if !isFileLeased(bucket: bucket, key: key) {
                try removeDiskRecord(bucket: bucket, key: key)
            }
            return nil
        }

        let accessedAtUS = CacheDateEncoding.microsecondsSinceEpoch(now)
        let updatedExpiresAtUS: Int64?
        switch record.expirationKind {
        case .never, .fixed:
            updatedExpiresAtUS = record.expiresAtUS
        case .sliding:
            guard let durationUS = record.expirationDurationUS else {
                throw CacheError.internalInconsistency("Sliding expiration is missing its duration.")
            }
            updatedExpiresAtUS = try CacheDateEncoding.adding(durationUS, to: accessedAtUS)
        }

        try diskIndex().updateAccess(
            entryID: record.id,
            lastAccessedAtUS: accessedAtUS,
            expiresAtUS: updatedExpiresAtUS
        )

        let token = leaseTable.acquire(LeaseIdentity(bucket: bucket, key: key))
        return CachedFileLease(
            url: fileURL,
            info: record.info(lastAccessedAtUS: accessedAtUS, expiresAtUS: updatedExpiresAtUS),
            token: token
        )
    }

    private func diskData(bucket: CacheBucketID, key: CacheKey) async throws -> CachedData? {
        guard let initialRecord = try diskIndex().fetchEntry(bucket: bucket, key: key),
              initialRecord.payloadKind == .data
        else {
            return nil
        }

        if initialRecord.info().isExpired(at: configuration.clock.now()) {
            try removeDiskRecord(bucket: bucket, key: key)
            return nil
        }

        let data = try await diskStore().readData(storageRef: initialRecord.storageRef)
        try Task.checkCancellation()

        guard let currentRecord = try diskIndex().fetchEntry(bucket: bucket, key: key),
              currentRecord.payloadKind == .data,
              currentRecord.storageRef == initialRecord.storageRef
        else {
            return nil
        }

        let accessedAt = configuration.clock.now()
        if currentRecord.info().isExpired(at: accessedAt) {
            try removeDiskRecord(bucket: bucket, key: key)
            return nil
        }

        let accessedAtUS = CacheDateEncoding.microsecondsSinceEpoch(accessedAt)
        let updatedExpiresAtUS: Int64?
        switch currentRecord.expirationKind {
        case .never, .fixed:
            updatedExpiresAtUS = currentRecord.expiresAtUS
        case .sliding:
            guard let durationUS = currentRecord.expirationDurationUS else {
                throw CacheError.internalInconsistency("Sliding expiration is missing its duration.")
            }
            updatedExpiresAtUS = try CacheDateEncoding.adding(durationUS, to: accessedAtUS)
        }

        try diskIndex().updateAccess(
            entryID: currentRecord.id,
            lastAccessedAtUS: accessedAtUS,
            expiresAtUS: updatedExpiresAtUS
        )

        return CachedData(
            data: data,
            info: currentRecord.info(lastAccessedAtUS: accessedAtUS, expiresAtUS: updatedExpiresAtUS)
        )
    }

    private func removeDiskRecord(bucket: CacheBucketID, key: CacheKey) throws {
        let removal = try diskIndex().removeEntry(bucket: bucket, key: key)
        let diskFileStore = try diskStore()
        diskFileStore.removeStorageRefsBestEffort(removal.1)
    }

    private func diskExpiration(
        _ policy: CacheExpirationPolicy,
        storedAtUS: Int64
    ) throws -> (kind: StoredExpirationKind, durationUS: Int64?, expiresAtUS: Int64?) {
        switch policy {
        case .never:
            return (.never, nil, nil)
        case .fixed(let duration):
            let durationUS = try CacheDurationEncoding.microseconds(duration)
            return (.fixed, durationUS, try CacheDateEncoding.adding(durationUS, to: storedAtUS))
        case .sliding(let duration):
            let durationUS = try CacheDurationEncoding.microseconds(duration)
            return (.sliding, durationUS, try CacheDateEncoding.adding(durationUS, to: storedAtUS))
        }
    }

    private func validateItemSize(_ size: ByteCount, bucket: CacheBucketID, policy: BucketPolicy) throws {
        if let maxItemSize = policy.maxItemSize, size > maxItemSize {
            throw CacheError.itemTooLarge(size: size, limit: maxItemSize)
        }

        guard size <= policy.maxTotalSize else {
            throw CacheError.capacityCannotBeSatisfied(
                bucket: bucket,
                constraint: .totalSize(requiredBytes: size, availableEvictableBytes: .zero)
            )
        }
    }

    private func resolvedFileExtension(sourceURL: URL, options: CacheFileOptions) throws -> String {
        if let explicitExtension = try CacheValidation.normalizedFileExtensionForInput(options.fileExtension) {
            return explicitExtension
        }

        let sourceExtension = sourceURL.pathExtension
        if !sourceExtension.isEmpty,
           let normalizedSourceExtension = CacheValidation.normalizedFileExtensionIfValid(sourceExtension) {
            return normalizedSourceExtension
        }

        return "bin"
    }

    private func throwIfExistingFileIsLeased(bucket: CacheBucketID, key: CacheKey) throws {
        guard let record = try diskIndex().fetchEntry(bucket: bucket, key: key), record.payloadKind == .file else {
            return
        }
        if isFileLeased(bucket: bucket, key: key) {
            throw CacheError.fileIsLeased(bucket: bucket, key: key)
        }
    }

    private func isFileLeased(bucket: CacheBucketID, key: CacheKey) -> Bool {
        leaseTable.isLeased(LeaseIdentity(bucket: bucket, key: key))
    }

    private func diskLeaseCheck() -> DiskFileLeaseCheck {
        let leaseTable = self.leaseTable
        return { bucket, key in
            leaseTable.isLeased(LeaseIdentity(bucket: bucket, key: key))
        }
    }

    private func requireFileStorage(_ policy: BucketPolicy) throws {
        if policy.storage == .memoryOnly {
            throw CacheError.unsupportedFileStorage(storageMode: policy.storage)
        }
    }

    private func diskStore() throws -> PersistentFileStore {
        guard let diskFileStore else {
            throw CacheError.internalInconsistency("Disk file store is unavailable.")
        }
        return diskFileStore
    }

    private func diskIndex() throws -> SQLiteMetadataIndex {
        guard let metadataIndex else {
            throw CacheError.internalInconsistency("SQLite metadata index is unavailable.")
        }
        return metadataIndex
    }

    private func combined(_ lhs: CacheRemovalResult, _ rhs: CacheRemovalResult) -> CacheRemovalResult {
        CacheRemovalResult(
            removedEntries: lhs.removedEntries + rhs.removedEntries,
            removedBytes: ByteCount.bytes(lhs.removedBytes.bytes + rhs.removedBytes.bytes),
            skippedLeasedEntries: lhs.skippedLeasedEntries + rhs.skippedLeasedEntries
        )
    }
}
