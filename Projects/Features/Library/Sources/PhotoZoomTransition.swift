import Core
import SwiftUI

/// 사진 상세 줌 전환의 출발점 식별자 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 같은 사진이 한 화면의 두 섹션(지역별 묶기, 여행 폴더 상세)이나 스택에 쌓인 두 화면(검색 결과 → 카테고리 화면)에 함께 있을 수 있어,
/// 연 곳(화면 방문 값 + 섹션 위치)과 사진 식별자를 함께 쓴다.
struct PhotoZoomSourceID: Hashable {
  let origin: PhotoDetailOrigin
  let id: ImageAsset.ID
}

extension EnvironmentValues {
  /// 사진 상세 줌 전환의 이름 공간. 보관함 NavigationStack 이 넣는다. 없으면(Example 미리보기) 상세는 보통 push 다.
  @Entry var photoZoomNamespace: Namespace.ID?
  /// 칸·줄이 속한 연 곳. 상세로 가는 링크가 자기 `PhotoDetailRoute.origin` 을 넣는다.
  @Entry var photoDetailOrigin: PhotoDetailOrigin?
}

extension View {
  /// 이 썸네일을 사진 상세 줌 전환의 출발점으로 삼는다. 이름 공간이나 연 곳이 없으면 아무것도 하지 않는다.
  /// - Parameter cornerRadius: 썸네일의 모서리. 닫힐 때 상세가 이 모양으로 줄어든다.
  func photoZoomSource(_ id: ImageAsset.ID, cornerRadius: CGFloat = 0) -> some View {
    self.modifier(PhotoZoomSourceModifier(id: id, cornerRadius: cornerRadius))
  }

  /// 사진 상세를 연 곳의 지금 장 썸네일에서 커지며 열리고, 그 썸네일로 줄어들며 닫히게 한다.
  /// 시스템 줌 전환이라 아래로 끌어 닫기(손가락을 따라 줄어듦)도 시스템이 한다. 연 곳이나 이름 공간이 없으면 보통 push 다.
  /// - Parameter id: 지금 장의 사진. 넘기면 바뀌어 닫힐 때 마지막으로 본 사진의 칸으로 돌아간다.
  func photoZoomDestination(origin: PhotoDetailOrigin?, id: ImageAsset.ID?) -> some View {
    self.modifier(PhotoZoomDestinationModifier(sourceID: origin.flatMap { origin in
      id.map { PhotoZoomSourceID(origin: origin, id: $0) }
    }))
  }
}

private struct PhotoZoomSourceModifier: ViewModifier {
  let id: ImageAsset.ID
  let cornerRadius: CGFloat
  @Environment(\.photoZoomNamespace) private var namespace
  @Environment(\.photoDetailOrigin) private var origin

  func body(content: Content) -> some View {
    if let namespace, let origin {
      content.matchedTransitionSource(id: PhotoZoomSourceID(origin: origin, id: self.id), in: namespace) { source in
        source.clipShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
      }
    } else {
      content
    }
  }
}

private struct PhotoZoomDestinationModifier: ViewModifier {
  let sourceID: PhotoZoomSourceID?
  @Environment(\.photoZoomNamespace) private var namespace

  func body(content: Content) -> some View {
    if let namespace, let sourceID {
      content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
    } else {
      content
    }
  }
}
