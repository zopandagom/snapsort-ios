import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.app(
  infoPlist: [
    "CFBundleDisplayName": "SnapSort",
    "NSPhotoLibraryUsageDescription": "보관함의 이미지를 기기 안에서 분석해 자동으로 분류하고, 필요 없는 사진을 골라 삭제할 수 있게 돕습니다. 사진은 외부로 전송되지 않습니다.",
  ],
  dependencies: [
    .feature(.library),
    .feature(.onboarding),
    .client(impl: .photoLibrary),
  ]
)
