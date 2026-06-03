import Foundation

internal enum CacheValidation {
    private static let maximumBucketIDLength = 128
    private static let maximumTagLength = 256
    private static let maximumKeyLength = 4096
    private static let maximumFileExtensionLength = 32

    static func validateConfiguration(_ configuration: CacheStoreConfiguration) throws {
        var seenBuckets = Set<CacheBucketID>()
        var hasDiskBackedBucket = false

        for bucket in configuration.buckets {
            try validateBucketIDForConfiguration(bucket.id)
            guard seenBuckets.insert(bucket.id).inserted else {
                throw CacheError.duplicateBucket(bucket.id)
            }

            if bucket.policy.storage == .diskBacked {
                hasDiskBackedBucket = true
            }

            try validatePolicy(bucket.policy, bucket: bucket.id)
        }

        if let rootDirectory = configuration.rootDirectory {
            guard rootDirectory.isFileURL else {
                throw CacheError.invalidConfiguration("Disk-backed cache root must be a file URL.")
            }
            guard hasDiskBackedBucket else {
                throw CacheError.invalidConfiguration("All-memory cache stores must use rootDirectory: nil.")
            }
        } else {
            guard !hasDiskBackedBucket else {
                throw CacheError.invalidConfiguration("Disk-backed buckets require a file URL rootDirectory.")
            }
        }
    }

    static func validateBucketIDForConfiguration(_ id: CacheBucketID) throws {
        try validateBucketID(id, error: CacheError.invalidConfiguration)
    }

    static func validateBucketIDForInput(_ id: CacheBucketID) throws {
        try validateBucketID(id, error: CacheError.invalidInput)
    }

    static func validateKeyForInput(_ key: CacheKey) throws {
        let value = key.rawValue
        guard !value.isEmpty else {
            throw CacheError.invalidInput("Cache key must not be empty.")
        }
        guard value.count <= maximumKeyLength else {
            throw CacheError.invalidInput("Cache key must be at most \(maximumKeyLength) characters.")
        }
        guard !containsControlCharacter(value) else {
            throw CacheError.invalidInput("Cache key must not contain NUL or control characters.")
        }
    }

    static func validateTagForInput(_ tag: CacheTag) throws {
        try validateTag(tag, error: CacheError.invalidInput)
    }

    static func validateEntryOptionsForInput(_ options: CacheEntryOptions) throws {
        try validateTagsForInput(options.tags)
    }

    static func validateFileOptionsForInput(_ options: CacheFileOptions) throws {
        try validateTagsForInput(options.tags)
        _ = try normalizedFileExtensionForInput(options.fileExtension)
    }

    static func normalizedFileExtensionForInput(_ fileExtension: String?) throws -> String? {
        guard let fileExtension else { return nil }
        return try normalizedFileExtension(fileExtension, error: CacheError.invalidInput)
    }

    static func normalizedFileExtensionIfValid(_ fileExtension: String) -> String? {
        try? normalizedFileExtension(fileExtension, error: CacheError.invalidInput)
    }

    private static func validateBucketID(
        _ id: CacheBucketID,
        error: (String) -> CacheError
    ) throws {
        let value = id.rawValue
        guard !value.isEmpty else {
            throw error("Cache bucket ID must not be empty.")
        }
        guard value != "." && value != ".." else {
            throw error("Cache bucket ID must not be '.' or '..'.")
        }
        guard value.count <= maximumBucketIDLength else {
            throw error("Cache bucket ID must be at most \(maximumBucketIDLength) characters.")
        }
        guard value.utf8.allSatisfy(isAllowedBucketIDByte(_:)) else {
            throw error("Cache bucket ID may contain only ASCII letters, numbers, '.', '_', and '-'.")
        }
    }

    private static func validatePolicy(_ policy: BucketPolicy, bucket: CacheBucketID) throws {
        guard policy.maxTotalSize.bytes > 0 else {
            throw CacheError.invalidConfiguration("Bucket '\(bucket.rawValue)' maxTotalSize must be greater than zero.")
        }

        if let maxItemSize = policy.maxItemSize {
            guard maxItemSize.bytes > 0 else {
                throw CacheError.invalidConfiguration("Bucket '\(bucket.rawValue)' maxItemSize must be greater than zero when provided.")
            }
            guard maxItemSize <= policy.maxTotalSize else {
                throw CacheError.invalidConfiguration("Bucket '\(bucket.rawValue)' maxItemSize must not exceed maxTotalSize.")
            }
        }

        if let maxItemCount = policy.maxItemCount {
            guard maxItemCount > 0 else {
                throw CacheError.invalidConfiguration("Bucket '\(bucket.rawValue)' maxItemCount must be greater than zero when provided.")
            }
        }

        switch policy.expiration {
        case .never:
            break
        case .fixed(let duration):
            try validatePositiveDuration(duration, bucket: bucket, policyName: "fixed expiration")
        case .sliding(let duration):
            try validatePositiveDuration(duration, bucket: bucket, policyName: "sliding expiration")
        }
    }

    private static func validatePositiveDuration(
        _ duration: Duration,
        bucket: CacheBucketID,
        policyName: String
    ) throws {
        guard duration > .zero else {
            throw CacheError.invalidConfiguration("Bucket '\(bucket.rawValue)' \(policyName) duration must be greater than zero.")
        }
    }

    private static func validateTagsForInput(_ tags: Set<CacheTag>) throws {
        for tag in tags {
            try validateTagForInput(tag)
        }
    }

    private static func validateTag(
        _ tag: CacheTag,
        error: (String) -> CacheError
    ) throws {
        let value = tag.rawValue
        guard !value.isEmpty else {
            throw error("Cache tag must not be empty.")
        }
        guard value.count <= maximumTagLength else {
            throw error("Cache tag must be at most \(maximumTagLength) characters.")
        }
        guard !containsControlCharacter(value) else {
            throw error("Cache tag must not contain NUL or control characters.")
        }
    }

    private static func normalizedFileExtension(
        _ fileExtension: String,
        error: (String) -> CacheError
    ) throws -> String {
        let normalized: String
        if fileExtension.first == "." {
            normalized = String(fileExtension.dropFirst())
        } else {
            normalized = fileExtension
        }

        guard !normalized.isEmpty else {
            throw error("Cache file extension must not be empty.")
        }
        guard normalized.first != "." else {
            throw error("Cache file extension may contain at most one optional leading dot.")
        }
        guard normalized.count <= maximumFileExtensionLength else {
            throw error("Cache file extension must be at most \(maximumFileExtensionLength) characters.")
        }
        guard !normalized.contains("/") && !normalized.contains("\\") else {
            throw error("Cache file extension must not contain path separators.")
        }
        guard !containsControlCharacter(normalized) else {
            throw error("Cache file extension must not contain NUL or control characters.")
        }

        return normalized
    }

    private static func isAllowedBucketIDByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "."),
             UInt8(ascii: "_"),
             UInt8(ascii: "-"):
            true
        default:
            false
        }
    }

    private static func containsControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.value <= 0x1F || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value)
        }
    }
}
