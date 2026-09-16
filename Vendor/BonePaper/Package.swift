// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BonePaper",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "BonePaper", targets: ["BonePaper"])
    ],
    targets: [
        .target(name: "BonePaper")
    ]
)
