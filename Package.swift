// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rename",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ConvertKit", targets: ["ConvertKit"]),
        .executable(name: "renamectl", targets: ["renamectl"]),
        .executable(name: "RenameApp", targets: ["RenameApp"]),
    ],
    targets: [
        .target(name: "ConvertKit"),
        .executableTarget(name: "renamectl", dependencies: ["ConvertKit"]),
        .executableTarget(name: "RenameApp", dependencies: ["ConvertKit"]),
        .testTarget(name: "ConvertKitTests", dependencies: ["ConvertKit"]),
    ]
)
