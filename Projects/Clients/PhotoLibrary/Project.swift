import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.client(
  .photoLibrary,
  implDependencies: [
    // presentLimitedLibraryPicker(from:) 는 PhotosUI 가 PHPhotoLibrary 에 붙이는 Objective-C 메서드라 링크할 심볼 참조가 없다.
    // 정적 프레임워크의 자동 링크만으로는 링커가 PhotosUI 를 빼 버려 실행 중 unrecognized selector 로 크래시하므로 명시한다.
    .sdk(name: "PhotosUI", type: .framework),
  ]
)
