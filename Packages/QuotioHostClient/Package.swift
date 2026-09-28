// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotioHostClient",
    platforms: [.macOS(.v14), .iOS(.v15)],
    products: [.library(name: "QuotioHostClient", targets: ["QuotioHostClient"])],
    targets: [
        .target(name: "QuotioHostClient"),
        .testTarget(name: "QuotioHostClientTests", dependencies: ["QuotioHostClient"]),
    ],
    swiftLanguageModes: [.v6]
)
