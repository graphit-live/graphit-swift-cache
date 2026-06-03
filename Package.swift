// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "GraphitCache",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "GraphitCache", targets: ["GraphitCache"])
    ],
    targets: [
        .target(
            name: "GraphitCache",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "GraphitCacheTests",
            dependencies: ["GraphitCache"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
