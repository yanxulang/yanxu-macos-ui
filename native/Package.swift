// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YanxuMacUIHost",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "YanxuMacUIHost", type: .dynamic, targets: ["YanxuMacUIHost"])
    ],
    targets: [
        .target(name: "YanxuMacUIHost")
    ]
)
