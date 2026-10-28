import SwiftUI

public extension View {
  /// 안쪽 여백을 두고 둥근 카드 면(모서리 20) 위에 올린다. 바탕은 `SnapColor.card`, 강조 카드는 `SnapColor.blush` 를 넘긴다.
  /// List 밖(ScrollView 등)에서 칸을 카드로 보일 때 쓴다. List 칸 색은 `SnapList` 가 정한다.
  func snapCard(_ fill: ColorToken = SnapColor.card, padding: CGFloat = 16) -> some View {
    self
      .padding(padding)
      .background(fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}
