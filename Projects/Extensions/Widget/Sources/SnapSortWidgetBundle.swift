import ExpiryWidgetFeature
import PhotoStoreImpl
import SwiftUI
import WidgetKit

/// 위젯 조립 지점. 저장소 Impl 을 읽기 전용으로 만들어 위젯 Feature 의 Provider 에 넘긴다 (docs/ARCHITECTURE.md §2).
@main
struct SnapSortWidgetBundle: WidgetBundle {
  var body: some Widget {
    ExpiryWidget()
  }
}

/// `Widget` 은 인자 없는 `init()` 이 필요해 Feature 가 저장소를 받는 Widget 을 줄 수 없으므로 여기서 만든다.
struct ExpiryWidget: Widget {
  var body: some WidgetConfiguration {
    ExpiryWidgetConfiguration.make(provider: ExpiryWidgetProvider(makeStore: Self.makeStore))
  }

  /// 타임라인을 만들 때마다 새로 연다. 앱이 저장 파일을 옮기거나 경량 이전한 뒤에도 같은 위젯 프로세스가 새 파일을 읽는다.
  /// 앱이 아직 저장 파일을 만들지 않았거나 열지 못하면 nil 이고, 위젯은 "앱을 열어 주세요"를 보인다.
  /// `Widget` 이 `@MainActor` 라 격리를 풀어야 Provider 가 메인 밖에서 부를 수 있다.
  private nonisolated static func makeStore() -> PhotoStoreClientImpl? {
    PhotoStoreClientImpl.sharedStoreURL(groupContainer: PhotoStoreClientImpl.appGroupContainer())
      .flatMap { try? PhotoStoreClientImpl(readingAt: $0) }
  }
}
