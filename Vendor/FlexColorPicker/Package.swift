// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlexColorPicker",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "FlexColorPicker", targets: ["FlexColorPicker"])
    ],
    targets: [
        .target(name: "FlexColorPicker")
    ]
)
