import SwiftUI

/// 화면 불러오기 표시. 로즈·라일락·버터 점 셋이 차례로 튄다(시안 Loading "준비 중").
/// VoiceOver 에서는 시스템 `ProgressView()` 와 똑같이 읽힌다. 동작 줄이기면 점이 멈춘다.
/// 버튼·줄 안의 작은 대기 표시는 시스템 `ProgressView` 를 그대로 쓴다.
public struct SnapLoadingDots: View {
  private static let period: TimeInterval = 1.1
  private static let dotSize: CGFloat = 14
  /// 버터 점은 시안의 장식이라 라이트 바탕과 대비가 낮다. 대기 표시로 읽히도록 나머지 두 점은 바탕·카드와 3:1 이상이다(`SnapColorTests`).
  public static let colors = [SnapColor.rose, SnapColor.lilac, SnapColor.butter]
  /// 점마다 0.15초씩 늦게 튄다.
  private static let delays: [TimeInterval] = [0, 0.15, 0.3]
  public static let bounce = LoopTrack([0: 0, 0.4: -10, 0.8: 0, 1: 0])

  public init() {}

  public var body: some View {
    LoopingTimeline(stillTime: 0) { time in
      HStack(spacing: 10) {
        ForEach(Self.colors.indices, id: \.self) { index in
          Circle()
            .fill(Self.colors[index])
            .frame(width: Self.dotSize, height: Self.dotSize)
            .offset(y: Self.bounce.value(at: (time - Self.delays[index]) / Self.period))
        }
      }
    }
    .frame(height: 34, alignment: .bottom)
    .accessibilityRepresentation {
      ProgressView()
    }
  }
}
