// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "xcframeworkmaker",
    platforms: [
        .macOS(.v13),
        .iOS(.v13)
    ],
    dependencies: [.package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
                   .package(url: "https://github.com/apple/swift-package-manager", branch: "main"),
                   .package(url: "https://github.com/kareman/SwiftShell.git", from: "5.1.0")],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "xcframeworkmaker",
            dependencies: [.product(name: "SwiftPM", package: "swift-package-manager"),
                           .product(name: "SwiftShell", package: "SwiftShell"),
                           .product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "Sources"),
    ]
)
