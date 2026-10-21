import SwiftUI

/// 썸네일 격자의 열과 간격. `LazyVGrid(columns:spacing:)` 에 함께 넘긴다.
public enum ThumbnailGrid {
  public static let spacing: CGFloat = 2
  /// 폭에 맞춰 칸 수가 정해지는 정사각형 격자 열 (iPhone 세로 3~4열).
  public static let columns = [GridItem(.adaptive(minimum: 96), spacing: Self.spacing)]
}
