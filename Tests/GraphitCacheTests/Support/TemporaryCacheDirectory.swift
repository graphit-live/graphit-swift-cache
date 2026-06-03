import Foundation

struct TemporaryCacheDirectory: Sendable {
    let url: URL

    init(name: String = UUID().uuidString) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GraphitCacheTests", isDirectory: true)
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        self.url = url
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
