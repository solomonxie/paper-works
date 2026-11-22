// swift-tools-version:6.0
import PackageDescription

// Pure Foundation: the rules that decide every date, tested on macOS with `swift test`.
let package = Package(
    name: "PaperWorksCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PaperWorksCore", targets: ["PaperWorksCore"])],
    targets: [
        .target(name: "PaperWorksCore", resources: [.process("Resources")]),
        .testTarget(name: "PaperWorksCoreTests", dependencies: ["PaperWorksCore"]),
    ]
)
