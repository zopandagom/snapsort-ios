import Testing
@testable import Core

/// 테스트의 OCR 줄은 지어낸 텍스트다. 앱 문구는 실행해 확인하지 못한 값이다 (docs/ARCHITECTURE.md §4 캡처 묶음 추출).
struct CaptureGroupExtractorChatAppTests {
  @Test(
    "줄 전체가 앱의 고유 문구와 같으면 그 앱이다",
    arguments: [
      ("여기까지 읽었습니다", ChatApp.kakaoTalk), ("여기까지 읽었습니다.", .kakaoTalk), ("iMessage", .messages),
      ("문자 메시지", .messages), ("Text Message", .messages),
    ]
  )
  func findsApp(_ text: String, _ app: ChatApp) {
    #expect(CaptureGroupExtractor.chatApp(in: ["오후 3:12", text, "안녕"]) == app)
  }

  @Test("문장 속에 든 문구나 문구가 없는 화면은 앱 모름이다", arguments: ["iMessage로 보내줘", "여기까지 읽었습니다 어제", "메시지 입력", "안녕하세요"])
  func doesNotFindApp(_ text: String) {
    #expect(CaptureGroupExtractor.chatApp(in: [text]) == nil)
  }

  @Test("서로 다른 앱의 문구가 함께 보이면 앱 모름이다")
  func twoAppsAreEmpty() {
    #expect(CaptureGroupExtractor.chatApp(in: ["여기까지 읽었습니다", "iMessage"]) == nil)
    #expect(CaptureGroupExtractor.chatApp(in: ["iMessage", "문자 메시지"]) == .messages)
  }

  @Test("문구가 없는 앱은 늘 앱 모름이다")
  func appsWithoutSignaturesAreNeverFound() {
    let empty = ChatApp.allCases.filter(\.signatures.isEmpty)
    #expect(Set(empty) == [.line, .telegram, .instagram, .whatsApp])
  }

  @Test("대화 카테고리일 때만 앱을 담는다")
  func extractsAppOnlyForChat() {
    let lines = [line("여기까지 읽었습니다")]

    #expect(CaptureGroupExtractor.extract(from: lines, categories: [.chat]).chatApp == .kakaoTalk)
    #expect(CaptureGroupExtractor.extract(from: lines, categories: [.shopping, .map]) == .empty)
  }
}

private func line(_ text: String) -> RecognizedTextLine {
  RecognizedTextLine(text: text, confidence: 0.9, boundingBox: .init(x: 0, y: 0, width: 1, height: 0.1))
}
