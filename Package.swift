// swift-tools-version: 6.0
import PackageDescription


let package = Package(
    name: "MultiCart",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        // Core domain, use cases, protocols
        .library(
            name: "MultiCartCore",
            targets: ["MultiCartCore"]
        ),

        // Core Data-based storage implementation
        .library(
            name: "MultiCartStorageCoreData",
            targets: ["MultiCartStorageCoreData"]
        ),

        // SwiftData-based storage implementation (iOS 17+ APIs inside)
        .library(
            name: "MultiCartStorageSwiftData",
            targets: ["MultiCartStorageSwiftData"]
        ),

        // Testing helpers (fakes, builders, in-memory stores)
        .library(
            name: "MultiCartTestingSupport",
            targets: ["MultiCartTestingSupport"]
        )
    ],
    dependencies: [
        // No external deps for now
    ],
    targets: [
        // MARK: - Core

        .target(
            name: "MultiCartCore",
            dependencies: []
        ),

        // MARK: - Storage

        .target(
            name: "MultiCartStorageCoreData",
            dependencies: [
                "MultiCartCore"
            ],
            resources: [
                .process("Resources")
            ]
        ),

        .target(
            name: "MultiCartStorageSwiftData",
            dependencies: [
                "MultiCartCore"
            ]
        ),

        // MARK: - Testing Support

        .target(
            name: "MultiCartTestingSupport",
            dependencies: [
                "MultiCartCore"
            ]
        ),

        // MARK: - Tests (placeholder for now)

        .testTarget(
            name: "MultiCartCoreTests",
            dependencies: [
                "MultiCartCore",
                "MultiCartTestingSupport"
            ]
        )
    ]
)
