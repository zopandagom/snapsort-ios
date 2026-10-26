import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.appExtension(
  .widget,
  dependencies: [
    .feature(.expiryWidget),
    // 위젯은 같은 저장 파일을 읽기 전용으로 연다 (docs/ARCHITECTURE.md §4 만료 임박 위젯).
    .client(impl: .photoStore),
    .shared(.core),
  ]
)
