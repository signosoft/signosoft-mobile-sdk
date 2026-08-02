// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "signosoft_signer",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .library(name: "signosoft-signer", targets: ["signosoft_signer"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // The one copy of the Swift core, reached through a symlink that lives
        // inside this package. It has to be inside: Flutter symlinks the whole
        // plugin package into ios/Flutter/ephemeral/Packages/.packages/ before
        // building, and SwiftPM resolves relative dependency paths against that
        // relocated path rather than the real one. A path that climbs out of
        // the package root (../../../ios) therefore resolves into ephemeral/
        // and fails; a path that stays inside resolves through the symlink and
        // lands on the real directory.
        .package(name: "SignosoftSigner", path: "SignosoftSignerCore"),
    ],
    targets: [
        .target(
            name: "signosoft_signer",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "SignosoftSigner", package: "SignosoftSigner"),
            ],
            resources: [.copy("PrivacyInfo.xcprivacy")]
        )
    ]
)
