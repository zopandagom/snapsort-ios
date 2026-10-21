/// 클립보드 (docs/ARCHITECTURE.md §4 캡처 정보 추출). 사용자가 누른 송장·계좌번호를 복사한다.
/// 구현은 PasteboardImpl, 테스트 대역은 PasteboardTesting 에 있다.
public protocol PasteboardClient: Sendable {
  /// 이 기기에서만 붙여 넣을 수 있게 글자를 복사한다(Universal Clipboard 로 다른 기기에 넘기지 않는다). 만료 시간은 두지 않는다.
  /// 사용자가 누를 때만 부른다. 복사한 글자는 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
  func copy(_ text: String) async
}
