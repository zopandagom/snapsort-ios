import PasteboardInterface
import UIKit

/// `UIPasteboard.general` 구현. 이 기기만(`localOnly`) 쓰고 만료 시간은 두지 않는다.
public struct PasteboardClientImpl: PasteboardClient {
  public init() {}

  public func copy(_ text: String) async {
    await Self.write(text)
  }

  /// 붙여 넣을 항목. 글자 하나를 형식 자동(`typeAutomatic`)으로 둔다.
  static func items(_ text: String) -> [[String: Any]] {
    [[UIPasteboard.typeAutomatic: text]]
  }

  /// 이 기기만. 만료 시간(`expirationDate`)은 넣지 않는다.
  static var options: [UIPasteboard.OptionsKey: Any] {
    [.localOnly: true]
  }

  /// `[String: Any]` 는 Sendable 이 아니므로 항목과 옵션을 메인에서 만든다.
  @MainActor
  private static func write(_ text: String) {
    UIPasteboard.general.setItems(self.items(text), options: self.options)
  }
}
