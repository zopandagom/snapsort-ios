import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.app(
  infoPlist: [
    "CFBundleDisplayName": .string(Env.displayName),
    "NSPhotoLibraryUsageDescription": "보관함의 이미지를 기기 안에서 분석해 자동으로 분류하고, 필요 없는 사진을 골라 삭제할 수 있게 돕습니다. 사진은 외부로 전송되지 않습니다.",
    // 제한 접근일 때 iOS 가 앱 실행마다 띄우는 "사진 더 선택" 알림을 끈다. 보관함 화면의 배너가 그 역할을 한다.
    "PHPhotoLibraryPreventAutomaticLimitedAccessAlert": true,
  ],
  dependencies: [
    .feature(.library),
    .feature(.onboarding),
    // Debug 빌드 전용 기록 도구. 모듈 소스가 모두 `#if DEBUG` 라 Release 에서는 빈 모듈이다 (docs/ARCHITECTURE.md §2).
    .feature(.sampleRecorder),
    .client(impl: .photoLibrary),
    .client(impl: .imageAnalysis),
    .client(impl: .photoStore),
    .client(impl: .classifier),
    .client(impl: .indexing),
    .client(impl: .notification),
    .client(impl: .map),
    .client(impl: .pasteboard),
    .client(impl: .widgetTimeline),
    // 만료 임박 위젯. App 의 PlugIns 에 임베드된다.
    .appExtension(.widget),
  ]
)
