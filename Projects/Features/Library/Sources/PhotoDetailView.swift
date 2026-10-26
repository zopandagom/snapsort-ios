import Core
import DesignSystem
import SwiftUI

/// 사진 상세: 기기에 있는 가장 큰 버전으로 한 장을 크게 보인다 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// iCloud 원본은 내려받지 않는다. 작은 대체 버전이면 안내를 붙이고, 기기 버전이 없으면 볼 수 없다고 보인다.
/// 아래에 캡처 행동(`CaptureActionsPanel`: 주소 지도 앱 열기·번호 복사, 기프티콘 목록·정리 화면에서 열었으면 기프티콘 정보·사용함·바코드)을 붙인다.
/// 읽은 이미지는 바코드 인식에 쓰도록 `captureModel` 로 넘긴다.
/// 닫히면(`.task` 취소) 두 Model 이 이미지와 캡처 행동 상태를 놓는다.
public struct PhotoDetailView: View {
  let model: CategoryModel
  let captureModel: CaptureActionsModel
  let route: PhotoDetailRoute

  init(model: CategoryModel, captureModel: CaptureActionsModel, route: PhotoDetailRoute) {
    self.model = model
    self.captureModel = captureModel
    self.route = route
  }

  /// - Parameter gifticon: 기프티콘 목록·정리 화면에서 열 때의 그 항목. nil 이면 주소·번호 행동만 보인다.
  public init(
    model: CategoryModel,
    captureModel: CaptureActionsModel,
    asset: ImageAsset,
    gifticon: GifticonListItem? = nil
  ) {
    self.init(model: model, captureModel: captureModel, route: PhotoDetailRoute(asset: asset, gifticon: gifticon))
  }

  private var asset: ImageAsset {
    self.route.asset
  }

  public var body: some View {
    self.contentView
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .safeAreaInset(edge: .bottom) {
        CaptureActionsPanel(model: self.captureModel, assetID: self.asset.id)
      }
      .navigationTitle(self.title)
      .navigationBarTitleDisplayMode(.inline)
      .task { await self.model.detailAppeared(id: self.asset.id) }
      .task { await self.captureModel.detailAppeared(id: self.asset.id, gifticon: self.route.gifticon) }
      // 이미지를 읽었거나 볼 수 없게 되면 바코드를 찾는다. 상세를 닫으면 취소된다.
      // 캡처 행동 상세가 열린 뒤에도 다시 돌도록 그 요청 번호를 키에 넣는다(두 `.task` 의 시작 순서에 기대지 않고,
      // 같은 사진을 닫았다 바로 다시 열어도 새 요청에서 다시 돈다).
      .task(id: self.imageKey) {
        guard self.imageKey.captureRequest != nil else { return }
        switch self.state {
        case let .loaded(image):
          await self.captureModel.detailImageLoaded(image, id: self.asset.id)
        case .unavailable:
          self.captureModel.detailImageUnavailable(id: self.asset.id)
        case .loading:
          break
        }
      }
  }

  private var imageKey: DetailImageKey {
    let phase: DetailImageKey.Phase = switch self.state {
    case .loading: .loading
    case .loaded: .loaded
    case .unavailable: .unavailable
    }
    let captureRequest = self.captureModel.detailID == self.asset.id ? self.captureModel.detailRequest : nil
    return DetailImageKey(id: self.asset.id, phase: phase, captureRequest: captureRequest)
  }

  /// 다른 사진의 상세 상태가 남아 있으면 쓰지 않고 불러오는 중으로 그린다.
  private var state: ImageLoadState {
    guard let detail = self.model.detail, detail.id == self.asset.id else { return .loading }
    return detail.state
  }

  @ViewBuilder
  private var contentView: some View {
    switch self.state {
    case .loading:
      ProgressView()
    case let .loaded(image):
      VStack(spacing: 12) {
        Image(decorative: image.cgImage, orientation: image.orientation)
          .resizable()
          .scaledToFit()
        if image.isLocalFallback {
          // 문구가 상태를 말하므로 심볼은 VoiceOver 에서 읽지 않는다.
          Label("iCloud 원본 대신 기기에 있는 작은 버전입니다", systemImage: "icloud")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("iCloud 원본 대신 기기에 있는 작은 버전입니다"))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
      }
    case .unavailable(.inCloudOnly):
      StatusMessageView(
        "iCloud 에만 있는 사진입니다",
        systemImage: "icloud.slash",
        description: "사진 앱에서 내려받으면 볼 수 있습니다."
      )
    case .unavailable(.notFound):
      StatusMessageView("보관함에 없는 사진입니다", systemImage: "photo.badge.exclamationmark")
    case .unavailable(.failed):
      // 다시 시도는 두지 않는다. 닫고 다시 열면 다시 읽는다.
      StatusMessageView("사진을 불러오지 못했습니다", systemImage: "exclamationmark.triangle")
    }
  }

  private var title: Text {
    if let date = self.asset.creationDate {
      Text(date, format: .dateTime.year().month().day().hour().minute())
    } else {
      Text("날짜 없음")
    }
  }
}

/// 상세 이미지 읽기 단계. 바코드 인식 `.task(id:)` 의 키다.
private struct DetailImageKey: Hashable {
  enum Phase: Hashable {
    case loading
    case loaded
    case unavailable
  }

  let id: ImageAsset.ID
  let phase: Phase
  /// 이 사진의 캡처 행동 상세 요청 번호. 열리기 전이면 nil.
  let captureRequest: Int?
}
