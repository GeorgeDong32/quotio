// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuotioForkExtras",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "QuotioForkExtras", targets: ["QuotioForkExtras"]),
    ],
    dependencies: [
        .package(path: "../QuotioCore"),
    ],
    targets: [
        .target(
            name: "QuotioForkExtras",
            dependencies: [
                .product(name: "QuotioDomain", package: "QuotioCore"),
                .product(name: "QuotioApplication", package: "QuotioCore"),
                .product(name: "QuotioInfrastructure", package: "QuotioCore"),
                .product(name: "QuotioPresentation", package: "QuotioCore"),
            ]
        ),
        .testTarget(
            name: "QuotioForkExtrasTests",
            dependencies: ["QuotioForkExtras"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
