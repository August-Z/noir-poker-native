// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PokerCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "PokerCore", targets: ["PokerCore"])],
    targets: [.target(name: "PokerCore"), .testTarget(name: "PokerCoreTests", dependencies: ["PokerCore"])]
)
