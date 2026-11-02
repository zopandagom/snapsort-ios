import DesignSystem
import SwiftUI
import UIKit

/// 권한을 아직 묻지 않았거나, 거부했거나, 제한된(스크린 타임·기기 관리) 상태를 보여준다.
/// 읽을 수 있는 권한이 생기면 App 이 보관함 화면으로 바꾸므로 여기서는 그 상태를 그리지 않는다.
/// 큰 글씨에서도 모든 글과 버튼에 닿도록 각 화면은 스크롤된다.
public struct OnboardingView: View {
  let model: OnboardingModel

  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// 첫 화면 등장을 시작했는지. 이 화면을 처음 볼 때 한 번 참이 된다.
  @State private var hasStartedIntro = false
  /// 기능 줄 아이콘이 튄 횟수(줄이 떠오를 때마다 하나씩 는다).
  @State private var bouncedFeatureCount = 0
  /// 등장을 마쳐 시작 버튼에 `snapGlow()` 를 건다.
  @State private var isStartButtonGlowing = false

  public init(model: OnboardingModel) {
    self.model = model
  }

  public var body: some View {
    self.content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(SnapColor.background)
      // 설정 앱에서 권한을 바꾸고 돌아오면 다시 읽는다. 시작 직후의 첫 값은 부르지 않는다(init 이 이미 읽었다).
      .onChange(of: self.scenePhase) { _, phase in
        guard phase == .active else { return }
        self.model.sceneBecameActive()
      }
  }

  @ViewBuilder
  private var content: some View {
    switch self.model.access {
    case .notDetermined:
      self.introduction
    case .denied:
      StatusScreen(
        systemImage: "lock",
        title: "사진 접근 권한이 필요해요",
        message: "설정 앱에서 사진 접근을 허용해 주세요. 일부 사진만 허용해도 돼요."
      ) {
        Button("설정 열기") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            self.openURL(url)
          }
        }
        .buttonStyle(.snapPrimary)
      }
    case .restricted:
      // 사용자가 이 앱 설정에서 바꿀 수 없는 상태라 설정 버튼 없이 이유만 알린다.
      StatusScreen(
        systemImage: "lock.slash",
        title: "사진 접근이 제한되어 있어요",
        message: "스크린 타임이나 기기 관리 설정이 이 기기의 사진 접근을 막고 있어요. 이 설정은 앱에서 바꿀 수 없으니, 기기를 관리하는 분께 문의해 주세요."
      ) {
        EmptyView()
      }
    case .authorized, .limited:
      EmptyView()
    }
  }

  /// 첫 화면: 앱 마크, 앱이 하는 일, 개인정보 약속, 제한 접근 안내. 시작 버튼은 아래에 고정해 큰 글씨에서도 늘 보인다.
  /// 권한 팝업의 버튼 이름은 OS 버전마다 달라 문구에 쓰지 않는다.
  /// 처음 볼 때 한 번 차례로 나타난다(`OnboardingIntro`): 앱 마크가 튀어 들어오고 → 제목 → 기능 세 줄(아이콘이 한 번씩 튐) →
  /// 개인정보 줄 → 시작 버튼이 떠오른 뒤 `snapGlow()`. 동작 줄이기면 위치·크기는 그대로 두고 투명도만 차례로 바꾼다.
  private var introduction: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        SnapPhotoStack(.appMark)
          .frame(width: 96, height: 96)
          .scaleEffect(self.hasStartedIntro || self.reduceMotion ? 1 : OnboardingIntro.markStartScale)
          .rotationEffect(.degrees(self.hasStartedIntro || self.reduceMotion ? 0 : OnboardingIntro.markStartDegrees))
          .opacity(self.hasStartedIntro ? 1 : 0)
          .animation(self.introAnimation(.mark), value: self.hasStartedIntro)

        Text("사진 보관함, 알아서 정리해 드릴게요")
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)
          .modifier(self.rise(.title))

        VStack(alignment: .leading, spacing: 20) {
          ForEach(Array(Self.features.enumerated()), id: \.offset) { index, feature in
            FeatureRow(
              systemImage: feature.systemImage,
              title: feature.title,
              message: feature.message,
              bounce: self.bouncedFeatureCount > index
            )
            .modifier(self.rise(.feature(index)))
          }
        }

        VStack(alignment: .leading, spacing: 28) {
          self.privacyNotice
        }
        .opacity(self.hasStartedIntro ? 1 : 0)
        .animation(self.introAnimation(.privacy), value: self.hasStartedIntro)
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollBounceBehavior(.basedOnSize)
    .safeAreaInset(edge: .bottom) {
      self.startButton
        .modifier(self.rise(.startButton))
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(SnapColor.background)
    }
    .task { await self.playIntroduction() }
  }

  /// 기능 세 줄. 실제 기능(카테고리 분류, 만료 알림·위젯, 정리 도우미)과 같게 적는다.
  private struct Feature {
    let systemImage: String
    let title: String
    let message: String
  }

  private static let features: [Feature] = [
    Feature(systemImage: "square.grid.2x2", title: "알아서 나눠요", message: "기프티콘·영수증·캡처·여행 사진을 자동으로"),
    Feature(systemImage: "bell.badge", title: "만료 전에 알려요", message: "기프티콘 만료일을 알림과 위젯으로"),
    Feature(systemImage: "sparkles", title: "깔끔하게 비워요", message: "지난 기프티콘·비슷한 사진 정리"),
  ]

  @ViewBuilder
  private var privacyNotice: some View {
    // 위치 좌표·주소 넘기기 예외까지 실제 데이터 흐름과 같게 적는다(ARCHITECTURE §4 위치·지도).
    FeatureRow(
      systemImage: "lock.shield",
      title: "사진과 사진 속 글자는 이 기기 안에서만 분석하고 밖으로 보내지 않아요.",
      message: "여행 장소 이름을 찾고 지도를 보여 주려고 여행지의 대략적인 위치 좌표와 언어·지역 설정만 "
        + "Apple 지도 서비스로 가고(지도를 움직이면 그 영역도), "
        + "주소를 눌러 지도 앱을 열 때만 그 주소를 지도 앱에 넘겨요."
    )

    PrivacyPolicyLink()

    Text("곧 뜨는 권한 창에서 일부 사진만 허용하면 고른 사진만 정리해요.")
      .font(.footnote)
      .foregroundStyle(.secondary)
  }

  /// 등장을 마친 뒤에만 빛을 건다(`snapGlow()` 는 나타날 때 번지므로 투명한 동안 걸면 보이지 않고 끝난다).
  @ViewBuilder
  private var startButton: some View {
    let button = Button {
      Task { await self.model.startButtonTapped() }
    } label: {
      Text("정리 시작하기")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.snapPrimary)
    .controlSize(.large)
    // 요청 중 복귀로 거부 화면이 돼도 "설정 열기"는 눌려야 하므로 이 버튼에만 건다.
    .disabled(self.model.isRequestingAccess)
    if self.isStartButtonGlowing {
      button.snapGlow()
    } else {
      button
    }
  }

  private func introAnimation(_ step: OnboardingIntro.Step) -> Animation {
    OnboardingIntro.animation(step, reduceMotion: self.reduceMotion)
  }

  private func rise(_ step: OnboardingIntro.Step) -> IntroRise {
    IntroRise(isShown: self.hasStartedIntro, reduceMotion: self.reduceMotion, animation: self.introAnimation(step))
  }

  /// 처음 볼 때 한 번 등장을 시작하고, 기능 줄이 떠오르는 때에 맞춰 아이콘을 튀긴 뒤 시작 버튼에 빛을 건다.
  /// 화면을 떠나 작업이 취소되면 기다림 없이 끝 상태로 둔다.
  private func playIntroduction() async {
    guard !self.hasStartedIntro else { return }
    self.hasStartedIntro = true
    var elapsed = 0.0
    if !self.reduceMotion {
      for index in Self.features.indices {
        let delay = OnboardingIntro.delay(.feature(index), reduceMotion: false)
        try? await Task.sleep(for: .seconds(delay - elapsed))
        elapsed = delay
        self.bouncedFeatureCount = index + 1
      }
    }
    let end = OnboardingIntro.glowDelay(reduceMotion: self.reduceMotion)
    try? await Task.sleep(for: .seconds(end - elapsed))
    self.isStartButtonGlowing = true
  }
}

/// 첫 화면 등장의 순서와 시간(초). 앱 마크 → 제목 → 기능 세 줄 → 개인정보 줄 → 시작 버튼.
enum OnboardingIntro {
  enum Step: Equatable {
    case mark
    case title
    case feature(Int)
    case privacy
    case startButton
  }

  /// 앱 마크가 튀어 들어오기 전의 배율과 기울기. 탄력 있는 스프링이라 1 을 조금 넘었다(약 1.1배·몇 도) 돌아온다.
  static let markStartScale: CGFloat = 0.3
  static let markStartDegrees: Double = -14
  /// 떠오르기 전 아래로 내려 둔 거리(pt).
  static let riseOffset: CGFloat = 16
  /// 동작 줄이기에서 다음 것이 나타나기까지의 간격과 투명도가 바뀌는 시간.
  static let reducedStep = 0.06
  static let reducedFade = 0.25

  /// 동작 줄이기에서의 순서(투명도만 `reducedStep` 간격으로).
  static func order(_ step: Step) -> Int {
    switch step {
    case .mark: 0
    case .title: 1
    case let .feature(index): 2 + index
    case .privacy: 5
    case .startButton: 6
    }
  }

  static func delay(_ step: Step, reduceMotion: Bool) -> Double {
    if reduceMotion {
      return Double(self.order(step)) * self.reducedStep
    }
    return switch step {
    case .mark: 0
    case .title: 0.25
    case let .feature(index): 0.52 + Double(index) * 0.15
    case .privacy: 1.05
    case .startButton: 1.15
    }
  }

  /// 시작 버튼이 다 떠오른 뒤 빛을 거는 때.
  static func glowDelay(reduceMotion: Bool) -> Double {
    self.delay(.startButton, reduceMotion: reduceMotion) + (reduceMotion ? self.reducedFade : 0.45)
  }

  static func animation(_ step: Step, reduceMotion: Bool) -> Animation {
    let base: Animation = if reduceMotion {
      .easeInOut(duration: self.reducedFade)
    } else {
      switch step {
      case .mark: .spring(duration: 0.65, bounce: 0.5)
      case .privacy: .easeOut(duration: 0.4)
      case .title, .feature, .startButton: .spring(response: 0.45, dampingFraction: 0.75)
      }
    }
    return base.delay(self.delay(step, reduceMotion: reduceMotion))
  }
}

/// 아래에서 떠오르며 나타난다. 동작 줄이기면 위치는 그대로 두고 투명도만 바꾼다.
private struct IntroRise: ViewModifier {
  let isShown: Bool
  let reduceMotion: Bool
  let animation: Animation

  func body(content: Content) -> some View {
    content
      .opacity(self.isShown ? 1 : 0)
      .offset(y: self.isShown || self.reduceMotion ? 0 : OnboardingIntro.riseOffset)
      .animation(self.animation, value: self.isShown)
  }
}

/// 아이콘 + 굵은 제목 + 설명 한 줄. VoiceOver 는 제목과 설명을 한 요소로 읽는다.
/// `bounce` 가 참이 되면 아이콘이 한 번 튄다.
private struct FeatureRow: View {
  let systemImage: String
  let title: String
  let message: String
  var bounce = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 14) {
      Image(systemName: self.systemImage)
        .font(.title3)
        .foregroundStyle(.tint)
        .symbolEffect(.bounce, value: self.bounce)
        .frame(minWidth: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(self.title)
          .font(.headline)
        Text(self.message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// 거부·제한 안내. 기본 크기에서는 세로 가운데에 두고, 큰 글씨로 넘치면 스크롤된다.
private struct StatusScreen<Actions: View>: View {
  let systemImage: String
  let title: String
  let message: String
  @ViewBuilder let actions: Actions

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        Image(systemName: self.systemImage)
          .font(.largeTitle)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Text(self.title)
          .font(.title2.bold())
          .accessibilityAddTraits(.isHeader)
        Text(self.message)
          .foregroundStyle(.secondary)
        self.actions
        // 거부·제한 상태에서는 보관함에 들어갈 수 없으므로 앱 안 처리방침 링크를 여기에도 둔다(심사 가이드라인 5.1.1(i)).
        PrivacyPolicyLink()
      }
      .multilineTextAlignment(.center)
      .padding(24)
      .frame(maxWidth: .infinity)
    }
    .scrollBounceBehavior(.basedOnSize)
    .defaultScrollAnchor(.center, for: .alignment)
  }
}
