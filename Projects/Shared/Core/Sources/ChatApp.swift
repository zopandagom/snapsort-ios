/// 대화 캡처의 앱 (docs/ARCHITECTURE.md §4 캡처 묶음 추출). rawValue 는 저장 키이므로 바꾸지 않는다.
public enum ChatApp: String, Sendable, Hashable, CaseIterable {
  case kakaoTalk, messages, line, telegram, instagram, whatsApp

  /// 섹션 이름.
  public var name: String {
    switch self {
    case .kakaoTalk: "카카오톡"
    case .messages: "메시지"
    case .line: "라인"
    case .telegram: "텔레그램"
    case .instagram: "인스타그램"
    case .whatsApp: "WhatsApp"
    }
  }

  /// 그 앱 화면에만 있는 고정 UI 문구(정규화한 줄 전체와 대조: 소문자, 공백 없음). 비어 있으면 그 앱은 늘 앱 모름이다.
  /// 모두 실행해 확인하지 못한 값이다(지식으로 적었다). 다른 앱에도 있을 수 있는 문구는 넣지 않는다.
  /// 실기기에서 확인하면 고친다. 바꾸면 `CaptureGroupExtractor.rulesVersion` 을 올린다.
  var signatures: [String] {
    switch self {
    case .kakaoTalk: ["여기까지읽었습니다"]
    case .messages: ["imessage", "문자메시지", "textmessage"]
    case .line, .telegram, .instagram, .whatsApp: []
    }
  }
}
