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

  /// 첫 화면: 앱이 하는 일, 개인정보 약속, 제한 접근 안내. 시작 버튼은 아래에 고정해 큰 글씨에서도 늘 보인다.
  /// 권한 팝업의 버튼 이름은 OS 버전마다 달라 문구에 쓰지 않는다.
  private var introduction: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        Text("사진 보관함, 알아서 정리해 드릴게요")
          .font(.largeTitle.bold())
          .accessibilityAddTraits(.isHeader)

        VStack(alignment: .leading, spacing: 20) {
          FeatureRow(
            systemImage: "square.grid.2x2",
            title: "자동 분류",
            message: "기프티콘·영수증·캡처·여행 사진을 카테고리별로 나눠요."
          )
          FeatureRow(
            systemImage: "bell.badge",
            title: "기프티콘 만료 알림",
            message: "만료일을 찾아 알림과 홈·잠금 화면 위젯으로 미리 알려 드려요."
          )
          FeatureRow(
            systemImage: "sparkles",
            title: "정리 도우미",
            message: "만료된 기프티콘, 비슷한 사진 같은 정리 후보를 모아 한 번에 정리해요."
          )
        }

        // 위치 좌표·주소 넘기기 예외까지 실제 데이터 흐름과 같게 적는다(ARCHITECTURE §4 위치·지도).
        FeatureRow(
          systemImage: "lock.shield",
          title: "사진과 사진 속 글자는 이 기기 안에서만 분석하고 밖으로 보내지 않아요.",
          message: "여행 장소 이름과 지도를 보여 줄 때만 대략적인 위치 좌표가 Apple 지도 서비스로 가고, 주소를 눌러 지도 앱을 열 때만 그 주소를 지도 앱에 넘겨요."
        )

        Text("곧 뜨는 권한 창에서 일부 사진만 허용하면 고른 사진만 정리해요.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollBounceBehavior(.basedOnSize)
    .safeAreaInset(edge: .bottom) {
      Button {
        Task { await self.model.startButtonTapped() }
      } label: {
        Text("정리 시작하기")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.snapPrimary)
      .controlSize(.large)
      // 요청 중 복귀로 거부 화면이 돼도 "설정 열기"는 눌려야 하므로 이 버튼에만 건다.
      .disabled(self.model.isRequestingAccess)
      .padding(.horizontal, 24)
      .padding(.vertical, 12)
      .background(SnapColor.background)
    }
  }
}

/// 아이콘 + 굵은 제목 + 설명 한 줄. VoiceOver 는 제목과 설명을 한 요소로 읽는다.
private struct FeatureRow: View {
  let systemImage: String
  let title: String
  let message: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 14) {
      Image(systemName: self.systemImage)
        .font(.title3)
        .foregroundStyle(.tint)
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
      }
      .multilineTextAlignment(.center)
      .padding(24)
      .frame(maxWidth: .infinity)
    }
    .scrollBounceBehavior(.basedOnSize)
    .defaultScrollAnchor(.center, for: .alignment)
  }
}
