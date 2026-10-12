import Foundation
import ImageAnalysisImpl
import IndexingImpl
import LibraryFeature
import OnboardingFeature
import PhotoLibraryImpl
import PhotoStoreImpl
import SwiftUI

/// 조립 지점. Client Impl 을 만들어 Feature Model 에 주입하는 곳은 여기뿐이다.
@main
struct SnapSortApp: App {
  @State private var onboardingModel: OnboardingModel
  @State private var libraryModel: LibraryModel
  /// 분류 결과 저장 위치. 상위 폴더는 저장소 전용이며 기기 백업에서 빠진다(PhotoStoreClientImpl).
  /// 위젯 작업(W4)에서 App Group 컨테이너로 바꾼다.
  private static let photoStoreURL = URL.applicationSupportDirectory
    .appending(path: "PhotoStore", directoryHint: .isDirectory)
    .appending(path: "PhotoStore.store")

  init() {
    let photoLibrary = PhotoLibraryClientImpl()
    self._onboardingModel = State(initialValue: OnboardingModel(photoLibrary: photoLibrary))
    // 저장소를 열지 못하면(디스크 공간 부족, 손상된 저장 파일 등) 인덱서 없이 보관함만 보여 준다.
    let indexing = (try? PhotoStoreClientImpl(url: Self.photoStoreURL)).map { photoStore in
      IndexingClientImpl(
        photoLibrary: photoLibrary,
        imageAnalysis: ImageAnalysisClientImpl(),
        photoStore: photoStore
      )
    }
    self._libraryModel = State(initialValue: LibraryModel(photoLibrary: photoLibrary, indexing: indexing))
  }

  var body: some Scene {
    WindowGroup {
      // 화면 간 흐름은 App 이 정한다. 읽을 수 있는 권한이 생기면 보관함으로 넘어간다.
      if self.onboardingModel.access.canRead {
        LibraryView(model: self.libraryModel)
      } else {
        OnboardingView(model: self.onboardingModel)
      }
    }
  }
}
