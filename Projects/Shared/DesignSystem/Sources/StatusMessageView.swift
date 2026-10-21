import SwiftUI

/// 빈 화면·불러오기 실패 안내. `ContentUnavailableView` 에 선택적 다시 시도 버튼을 붙인다.
public struct StatusMessageView: View {
  private let title: String
  private let systemImage: String
  private let description: String?
  private let retry: (() -> Void)?

  /// - Parameter retry: 정하면 "다시 시도" 버튼을 보이고 누를 때 부른다.
  public init(_ title: String, systemImage: String, description: String? = nil, retry: (() -> Void)? = nil) {
    self.title = title
    self.systemImage = systemImage
    self.description = description
    self.retry = retry
  }

  public var body: some View {
    ContentUnavailableView {
      // 제목이 상태를 말하므로 심볼은 VoiceOver 에서 읽지 않는다.
      Label(self.title, systemImage: self.systemImage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(self.title))
    } description: {
      if let description = self.description {
        Text(description)
      }
    } actions: {
      if let retry = self.retry {
        Button("다시 시도", action: retry)
          .buttonStyle(.bordered)
      }
    }
  }
}
