import GraphitCache
import Testing

func expectCacheError(
    _ operation: () throws -> Void,
    matching matches: (CacheError) -> Bool
) {
    do {
        try operation()
        Issue.record("Expected CacheError, but operation succeeded.")
    } catch let error as CacheError {
        #expect(matches(error), "Unexpected CacheError: \(error.description)")
    } catch {
        Issue.record("Expected CacheError, but received: \(error)")
    }
}

func expectCacheError(
    _ operation: () async throws -> Void,
    matching matches: (CacheError) -> Bool
) async {
    do {
        try await operation()
        Issue.record("Expected CacheError, but operation succeeded.")
    } catch let error as CacheError {
        #expect(matches(error), "Unexpected CacheError: \(error.description)")
    } catch {
        Issue.record("Expected CacheError, but received: \(error)")
    }
}
