import Testing
import UIKit
@testable import PasteboardImpl

struct PasteboardClientImplTests {
  @Test("이 기기에서만 붙여 넣게 하고 만료 시간은 두지 않는다")
  func usesLocalOnlyWithoutExpiration() {
    let options = PasteboardClientImpl.options

    #expect(options[.localOnly] as? Bool == true)
    #expect(options[.expirationDate] == nil)
    #expect(options.count == 1)
  }

  @Test("글자 하나를 형식 자동 항목으로 그대로 넣는다")
  func makesSingleAutomaticItem() {
    let items = PasteboardClientImpl.items("1234-5678-9012")

    #expect(items.count == 1)
    #expect(items.first?.count == 1)
    #expect(items.first?[UIPasteboard.typeAutomatic] as? String == "1234-5678-9012")
  }
}
