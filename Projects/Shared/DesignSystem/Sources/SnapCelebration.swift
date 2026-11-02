import Foundation

/// 분류 완료 축하 카드의 화면 움직임 기준값. 카드가 머무는 시간은 Model 동작이라 LibraryModel 이 갖는다.
public enum SnapCelebration {
  /// 동작 줄이기(Reduce Motion)에서 축하 카드가 나타나고 접힐 때의 투명도 전환 시간(초).
  public static let reducedFade = 0.25
}
