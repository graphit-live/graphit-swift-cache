import Synchronization

internal struct LeaseIdentity: Hashable, Sendable {
    var bucket: CacheBucketID
    var key: CacheKey
}

internal final class LeaseTable: Sendable {
    private let counts = Mutex<[LeaseIdentity: Int]>([:])

    func acquire(_ identity: LeaseIdentity) -> LeaseToken {
        counts.withLock { counts in
            counts[identity, default: 0] += 1
        }
        return LeaseToken(identity: identity, table: self)
    }

    func isLeased(_ identity: LeaseIdentity) -> Bool {
        counts.withLock { counts in
            (counts[identity] ?? 0) > 0
        }
    }

    fileprivate func release(_ identity: LeaseIdentity) {
        counts.withLock { counts in
            guard let count = counts[identity], count > 0 else {
                return
            }

            if count == 1 {
                counts.removeValue(forKey: identity)
            } else {
                counts[identity] = count - 1
            }
        }
    }
}

internal final class LeaseToken: Sendable {
    private let identity: LeaseIdentity
    private let table: LeaseTable
    private let released = Mutex(false)

    init(identity: LeaseIdentity, table: LeaseTable) {
        self.identity = identity
        self.table = table
    }

    func release() {
        let shouldRelease = released.withLock { released in
            if released {
                return false
            }
            released = true
            return true
        }

        if shouldRelease {
            table.release(identity)
        }
    }

    deinit {
        release()
    }
}
