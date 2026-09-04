// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Suffix",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ConvertKit", targets: ["ConvertKit"]),
        .executable(name: "suffixctl", targets: ["suffixctl"]),
        .executable(name: "SuffixApp", targets: ["SuffixApp"]),
    ],
    targets: [
        .target(name: "ConvertKit"),
        .executableTarget(name: "suffixctl", dependencies: ["ConvertKit"]),
        .executableTarget(name: "SuffixApp", dependencies: ["ConvertKit"]),
        .testTarget(name: "ConvertKitTests", dependencies: ["ConvertKit"]),
    ]
)
