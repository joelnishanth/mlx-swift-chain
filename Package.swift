// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "mlx-swift-chain",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MLXSwiftChain", targets: ["MLXSwiftChain"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MLXSwiftChain",
            dependencies: []
        ),
        .testTarget(
            name: "MLXSwiftChainTests",
            dependencies: ["MLXSwiftChain"]
        ),
    ]
)
