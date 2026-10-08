import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.app(
  infoPlist: [
    "CFBundleDisplayName": "SnapSort",
    "NSPhotoLibraryUsageDescription": "스크린샷을 기기 안에서 분석해 자동으로 정리합니다. 사진은 외부로 전송되지 않습니다.",
  ],
  dependencies: [
    .feature(.library),
    .feature(.onboarding),
    .client(impl: .photoLibrary),
  ]
)
