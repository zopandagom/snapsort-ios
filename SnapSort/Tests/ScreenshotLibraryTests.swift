import Testing
@testable import SnapSort

struct ScreenshotLibraryTests {
  @Test func accessStateIsReadableWithoutPrompt() {
    // 권한 팝업 없이 현재 상태를 읽을 수 있어야 온보딩 분기가 가능하다.
    _ = ScreenshotLibrary().accessState()
  }
}
