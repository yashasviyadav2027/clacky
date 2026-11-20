// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clacky",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ObjCCatch", path: "Sources/ObjCCatch"),
        .executableTarget(name: "Clacky", dependencies: ["ObjCCatch"], path: "Sources/Clacky")
    ]
)
