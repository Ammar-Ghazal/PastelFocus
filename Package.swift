// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PastelFocusCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PastelFocusCore", targets: ["PastelFocusCore"]),
    ],
    targets: [
        .target(
            name: "PastelFocusCore",
            path: "Sources/PastelFocusCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "PastelFocusCoreTests",
            dependencies: ["PastelFocusCore"],
            path: "Tests/PastelFocusCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
