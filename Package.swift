// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Topsort-Analytics",
    platforms: [
        .macOS("12.00"),
        .iOS("15.0"),
        .tvOS("11.0"),
        .watchOS("7.1")],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Topsort-Analytics",
            targets: ["Topsort-Analytics"]),
        .library(
            name: "TopsortBanners",
            targets: ["TopsortBanners"]
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Topsort-Analytics"),
        .testTarget(
            name: "analytics.swiftTests",
            dependencies: ["Topsort-Analytics"]),
        .target(
            name: "TopsortBanners",
            dependencies: ["Topsort-Analytics"]),
        // .testTarget(
        //     name: "banners.swiftTests",
        //     dependencies: ["Topsort-Banners"])

    ]
)
