// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SignosoftSigner",
    // iOS is the product platform. macOS is declared only so `swift test` can
    // run the model and parsing tests on a Mac with no simulator — every UIKit
    // source is behind `#if canImport(UIKit)`.
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SignosoftSigner", targets: ["SignosoftSigner"]),
    ],
    targets: [
        .target(
            name: "SignosoftSigner",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "SignosoftSignerTests",
            dependencies: ["SignosoftSigner"]
        ),
    ]
)
