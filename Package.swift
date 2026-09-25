// swift-tools-version: 6.0
// SwiftPM manifest so `swift run` and `swift test` work from the CLI.
// The canonical build for shipping and CI remains the XcodeGen project
// (`xcodegen generate && xcodebuild`), which additionally applies the app
// sandbox entitlements and generated Info.plist. This manifest builds the
// same sources as a bare executable for local development.
import PackageDescription

let package = Package(
    name: "PaashERP",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "PaashERP", targets: ["PaashERP"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "PaashERP",
            dependencies: [
                .product(name: "GRDB", package: "grdb.swift")
            ],
            path: "Sources",
            // Asset catalogs are compiled by Xcode, not SwiftPM, and the app
            // never reads bundled resources.
            exclude: ["Assets.xcassets"]
        ),
        .testTarget(
            name: "PaashERPTests",
            dependencies: [
                "PaashERP",
                .product(name: "GRDB", package: "grdb.swift")
            ],
            path: "Tests"
        )
    ],
    swiftLanguageModes: [.v6]
)
