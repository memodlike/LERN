// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LERN",
    platforms: [.macOS(.v14), .iOS(.v18), .watchOS(.v11)],
    products: [.library(name: "LERNCore", targets: ["LERNCore"])],
    targets: [
        .target(name: "LERNCore", exclude: ["LERN-Info.plist"]),
        .testTarget(name: "LERNCoreTests", dependencies: ["LERNCore"])
    ],
    swiftLanguageModes: [.v5]
)
