// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "mlx-swift-chain",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MLXSwiftChain", targets: ["MLXSwiftChain"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
    ],
    targets: [
        .target(
            name: "MLXSwiftChain",
            dependencies: [
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ]
        ),
        .testTarget(
            name: "MLXSwiftChainTests",
            dependencies: ["MLXSwiftChain"]
        ),
    ]
)
