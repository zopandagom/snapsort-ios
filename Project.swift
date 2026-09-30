import ProjectDescription

let bundleIdPrefix = "com.zopandagom"

let project = Project(
  name: "SnapSort",
  options: .options(
    defaultKnownRegions: ["ko", "en"],
    developmentRegion: "ko"
  ),
  settings: .settings(
    base: [
      "SWIFT_VERSION": "6.0",
      "SWIFT_STRICT_CONCURRENCY": "complete"
    ]
  ),
  targets: [
    .target(
      name: "SnapSort",
      destinations: .iOS,
      product: .app,
      bundleId: "\(bundleIdPrefix).snapsort",
      deploymentTargets: .iOS("26.0"),
      infoPlist: .extendingDefault(with: [
        "UILaunchScreen": [:],
        "CFBundleDisplayName": "SnapSort",
        "NSPhotoLibraryUsageDescription": "스크린샷을 기기 안에서 분석해 자동으로 정리합니다. 사진은 외부로 전송되지 않습니다."
      ]),
      sources: ["SnapSort/Sources/**"],
      resources: ["SnapSort/Resources/**"]
    ),
    .target(
      name: "SnapSortTests",
      destinations: .iOS,
      product: .unitTests,
      bundleId: "\(bundleIdPrefix).snapsort.tests",
      deploymentTargets: .iOS("26.0"),
      sources: ["SnapSort/Tests/**"],
      dependencies: [.target(name: "SnapSort")]
    )
  ]
)
