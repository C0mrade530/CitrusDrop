// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CitrusDrop", platforms: [.macOS(.v13)], products: [.executable(name: "CitrusDrop", targets: ["CitrusDrop"])], targets: [.executableTarget(name: "CitrusDrop")])
