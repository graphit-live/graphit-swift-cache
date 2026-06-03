import Foundation

/// A retained lease for a cache-managed file URL.
///
/// The lease must be retained for as long as the caller uses `url`. Releasing the lease allows
/// GraphitCache to remove or replace the file in later operations.
public final class CachedFileLease: Sendable {
    /// The cache-managed file URL protected by this lease.
    public let url: URL

    /// Metadata describing the leased file entry.
    public let info: CacheEntryInfo

    init(url: URL, info: CacheEntryInfo) {
        self.url = url
        self.info = info
    }

    /// Releases the lease.
    ///
    /// Calling `release()` more than once is safe. Callers should release explicitly when they are
    /// finished using the file URL; `deinit` is only a safety net.
    public func release() {}

    deinit {
        release()
    }
}
