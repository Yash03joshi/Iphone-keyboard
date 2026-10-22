// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KeshuKeyboard",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        // xtool: the app (see `product` in xtool.yml) and its keyboard extension.
        .library(name: "KeshuApp", targets: ["KeshuApp"]),
        .library(name: "KeshuKeyboard", targets: ["KeshuKeyboard"]),
    ],
    dependencies: [
        // Google ships ML Kit for iOS only via CocoaPods; this repackages it for SwiftPM.
        .package(url: "https://github.com/d-date/google-mlkit-swiftpm", exact: "9.0.2"),
    ],
    targets: [
        .target(name: "KeshuApp"),
        .target(
            name: "KeshuKeyboard",
            dependencies: [
                .product(name: "MLKitDigitalInkRecognition", package: "google-mlkit-swiftpm"),
            ],
            linkerSettings: [
                // ML Kit's static archives register classes via ObjC categories/initialisers;
                // without these the linker drops them and recognition fails at runtime.
                .unsafeFlags(["-ObjC", "-all_load"]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
