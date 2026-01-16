// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "union-image",
    platforms: [.iOS(.v26)],
    products: [
        .library(
            name: "UnionImage",
            targets: ["UnionImage"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/TimOliver/TOCropViewController.git",
            from: "2.7.0"
        )
    ],
    targets: [
        .target(
            name: "UnionImage",
            dependencies: [
                .product(
                    name: "CropViewController",
                    package: "TOCropViewController"
                )
            ]
        )
    ]
)
