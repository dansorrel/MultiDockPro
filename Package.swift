// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiDockPro",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MultiDockPro", targets: ["MultiDockPro"])
    ],
    targets: [
        .executableTarget(
            name: "MultiDockPro",
            path: "Sources"
        )
    ]
)
