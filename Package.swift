// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Topsort",
    platforms: [
        .macOS("12.00"),
        .iOS("15.0"),
        .tvOS("11.0"),
        .watchOS("7.1")],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Topsort",
            targets: ["Topsort"]),
        .library(
            name: "TopsortBanners",
            targets: ["TopsortBanners"]
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Topsort"),
        .testTarget(
            name: "topsort.swiftTests",
            dependencies: ["Topsort"]),
        .target(
            name: "TopsortBanners",
            dependencies: ["Topsort"]),
        .testTarget(
            name: "banners.swiftTests",
            dependencies: ["TopsortBanners", "Topsort"]),

    ]
)
