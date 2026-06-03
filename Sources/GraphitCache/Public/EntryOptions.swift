import Foundation

/// Options applied when storing a `Data` entry.
public struct CacheEntryOptions: Sendable, Hashable {
    /// App-defined grouping tags associated with the entry.
    public var tags: Set<CacheTag>

    /// Creates data entry options.
    ///
    /// - Parameter tags: App-defined grouping tags associated with the entry.
    public init(tags: Set<CacheTag> = []) {
        self.tags = tags
    }
}

/// Options applied when importing a file entry.
public struct CacheFileOptions: Sendable, Hashable {
    /// App-defined grouping tags associated with the entry.
    public var tags: Set<CacheTag>

    /// An optional file path extension hint for the managed cache file.
    ///
    /// This value is not MIME or content-type metadata.
    public var fileExtension: String?

    /// Creates file entry options.
    ///
    /// - Parameters:
    ///   - tags: App-defined grouping tags associated with the entry.
    ///   - fileExtension: An optional file path extension hint for the managed cache file.
    public init(tags: Set<CacheTag> = [], fileExtension: String? = nil) {
        self.tags = tags
        self.fileExtension = fileExtension
    }
}
