// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-tategaki",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "Tategaki", targets: ["Tategaki"]),
    ],
    targets: [
        .target(name: "Tategaki"),
        .testTarget(name: "TategakiTests", dependencies: ["Tategaki"]),
    ]
)
