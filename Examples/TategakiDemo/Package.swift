// swift-tools-version: 6.0
import PackageDescription

// A small Mac app for trying the library by hand. It is a package of its own, so the library has no demo product.
let package = Package(
    name: "TategakiDemo",
    platforms: [.macOS(.v14)],
    // Named, so that it resolves whatever the folder this repository was cloned into is called.
    dependencies: [.package(name: "swift-tategaki", path: "../..")],
    targets: [
        .executableTarget(name: "TategakiDemo", dependencies: [.product(name: "Tategaki", package: "swift-tategaki")]),
    ]
)
