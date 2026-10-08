import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.app(
  infoPlist: [
    "CFBundleDisplayName": "SnapSort",
    "NSPhotoLibraryUsageDescription": "보관함의 이미지를 기기 안에서 분석해 자동으로 분류하고, 필요 없는 사진을 골라 삭제할 수 있게 돕습니다. 사진은 외부로 전송되지 않습니다.",
    // 제한 접근일 때 iOS 가 앱 실행마다 띄우는 "사진 더 선택" 알림을 끈다. 보관함 화면의 배너가 그 역할을 한다.
    "PHPhotoLibraryPreventAutomaticLimitedAccessAlert": true,
  ],
  dependencies: [
    .feature(.library),
    .feature(.onboarding),
    .client(impl: .photoLibrary),
  ]
)
