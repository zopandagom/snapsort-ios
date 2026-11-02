import Core
import DesignSystem
import SwiftUI

/// 사진 상세: 기기에 있는 가장 큰 버전으로 보이고, 연 화면의 누른 섹션 안에서 좌우로 넘긴다 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 넘기기 순서는 연 때의 섹션 스냅숏(`PhotoDetailRoute.pages`)이고 섹션 끝에서 멈춘다. 장마다 핀치·더블탭으로 확대하고(`ZoomableImageView`),
/// 넘기면 확대는 1배로 돌아간다. 원본은 `CategoryModel` 이 지금 장 ± 1 만 들고(`detailImages`), 지금 장을 먼저 읽는다.
/// iCloud 원본은 내려받지 않는다. 작은 대체 버전이면 안내를 붙이고, 기기 버전이 없으면 그 장에 볼 수 없다고 보인다.
/// 아래에 지금 장의 캡처 행동(`CaptureActionsPanel`: 주소 지도 앱 열기·번호 복사, 기프티콘 목록·정리 화면의 기프티콘 후보에서 연 장이면
/// 기프티콘 정보·사용함·바코드)을 붙인다. 지금 장의 이미지는 바코드 인식에 쓰도록 `captureModel` 로 넘긴다.
/// 지금 장(`committedIndex`)은 스크롤이 멈췄을 때 정한다: 반쯤 끌다 되돌리면 창·패널·제목이 바뀌지 않는다.
/// 지금 장이 바뀌면 `CategoryModel.detailPageChanged` 로 창과 돌아올 위치를 옮긴다.
/// 닫히면(`.task` 취소) 두 Model 이 이미지와 캡처 행동 상태를 놓는다.
public struct PhotoDetailView: View {
  let model: CategoryModel
  let captureModel: CaptureActionsModel
  let route: PhotoDetailRoute

  /// 페이저의 스크롤 위치. `.scrollPosition(id:)` 에만 잇고, 지금 장으로는 `committedIndex` 를 읽는다.
  @State private var position: Int?
  /// 지금 장. 패널·제목·창·바코드·확대 초기화가 모두 이 값을 쓴다.
  @State private var committedIndex: Int
  /// 페이저의 스크롤 단계. 멈춰 있을 때의 위치 변화(접근성 동작)는 바로 지금 장으로 정한다.
  @State private var scrollPhase: ScrollPhase = .idle

  init(model: CategoryModel, captureModel: CaptureActionsModel, route: PhotoDetailRoute) {
    self.model = model
    self.captureModel = captureModel
    self.route = route
    self._position = State(initialValue: route.index)
    self._committedIndex = State(initialValue: route.index)
  }

  /// 한 장 상세.
  /// - Parameter gifticon: 기프티콘 목록·정리 화면에서 열 때의 그 항목. nil 이면 주소·번호 행동만 보인다.
  public init(
    model: CategoryModel,
    captureModel: CaptureActionsModel,
    asset: ImageAsset,
    gifticon: GifticonListItem? = nil
  ) {
    self.init(model: model, captureModel: captureModel, route: PhotoDetailRoute(asset: asset, gifticon: gifticon))
  }

  /// 여러 장 상세(Example). 돌아올 위치는 없다.
  /// - Parameters:
  ///   - pages: 비어 있지 않은 한 섹션의 장들.
  ///   - index: 처음 보일 장.
  public init(model: CategoryModel, captureModel: CaptureActionsModel, pages: [PhotoPage], index: Int) {
    self.init(
      model: model,
      captureModel: captureModel,
      route: PhotoDetailRoute(pages: pages, index: index, origin: nil)
    )
  }

  private var page: PhotoPage? {
    self.route.pages.indices.contains(self.committedIndex) ? self.route.pages[self.committedIndex] : nil
  }

  public var body: some View {
    self.pager
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .safeAreaInset(edge: .bottom) {
        if let page = self.page {
          // 장마다 새로 만들어 바코드 크게 보기·복사 안내 같은 패널의 화면 일시 상태가 지난 장에서 이어지지 않게 한다.
          CaptureActionsPanel(model: self.captureModel, assetID: page.asset.id)
            .id(self.committedIndex)
        }
      }
      .navigationTitle(self.title)
      .snapScreenBackground()
      .navigationBarTitleDisplayMode(.inline)
      .task {
        await self.model.detailAppeared(
          ids: self.route.pages.map(\.asset.id),
          // 처음 누른 위치가 아니라 지금 장으로 연다. 상세가 스택에 남은 채 이 `.task` 가 다시 시작돼도 창·돌아올 위치가 지금 장 기준이다.
          index: self.committedIndex,
          origin: self.route.origin
        )
      }
      .onChange(of: self.committedIndex) {
        guard let page = self.page else { return }
        self.model.detailPageChanged(index: self.committedIndex, id: page.asset.id)
      }
      // 장이 바뀌면 지난 장의 Task 를 취소하고 새 요청으로 다시 시작한다. 지난 장의 늦은 결과는 Model 의 요청 번호가 버린다.
      .task(id: PageKey(index: self.committedIndex, id: self.page?.asset.id)) {
        guard let page = self.page else { return }
        await self.captureModel.detailAppeared(id: page.asset.id, gifticon: page.gifticon)
      }
      // 지금 장 이미지를 읽었거나 볼 수 없게 되면 바코드를 찾는다. 상세를 닫거나 다른 장으로 넘기면 취소된다.
      // 캡처 행동 상세가 열린 뒤에도 다시 돌도록 그 요청 번호를 키에 넣는다(두 `.task` 의 시작 순서에 기대지 않고,
      // 같은 장으로 돌아오거나 같은 사진을 닫았다 바로 다시 열어도 새 요청에서 다시 돈다).
      .task(id: self.imageKey) {
        guard let key = self.imageKey, key.captureRequest != nil else { return }
        switch self.state(of: key.id) {
        case let .loaded(image):
          await self.captureModel.detailImageLoaded(image, id: key.id)
        case .unavailable:
          self.captureModel.detailImageUnavailable(id: key.id)
        case .loading:
          break
        }
      }
  }

  private var pager: some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 0) {
        ForEach(self.route.pages.indices, id: \.self) { index in
          PhotoPageView(
            model: self.model,
            page: self.route.pages[index],
            isCurrent: index == self.committedIndex
          )
          .containerRelativeFrame([.horizontal, .vertical])
          .accessibilityAction(named: Text("이전 사진")) { self.move(by: -1) }
          .accessibilityAction(named: Text("다음 사진")) { self.move(by: 1) }
        }
      }
      .scrollTargetLayout()
    }
    .scrollTargetBehavior(.paging)
    .scrollIndicators(.hidden)
    .scrollPosition(id: self.$position)
    // 스크롤이 멈출 때의 위치를 지금 장으로 정한다. 끌거나 관성으로 가는 중의 위치 변화는 정하지 않는다.
    // 멈춤과 위치 변화 중 어느 쪽이 먼저 와도 마지막 위치가 정해지게 두 곳에서 본다.
    .onScrollPhaseChange { _, phase in
      self.scrollPhase = phase
      if phase == .idle {
        self.commit(self.position)
      }
    }
    .onChange(of: self.position) {
      if self.scrollPhase == .idle {
        self.commit(self.position)
      }
    }
  }

  private func commit(_ position: Int?) {
    guard let position, self.route.pages.indices.contains(position), position != self.committedIndex else { return }
    self.committedIndex = position
  }

  /// 접근성 동작: 페이저를 옮기고, 멈춘 상태의 위치 변화로 지금 장이 정해진다. 섹션 끝이면 아무것도 하지 않는다.
  private func move(by offset: Int) {
    let target = self.committedIndex + offset
    guard self.route.pages.indices.contains(target) else { return }
    self.position = target
  }

  private func state(of id: ImageAsset.ID) -> ImageLoadState {
    self.model.detailImages[id] ?? .loading
  }

  private var imageKey: DetailImageKey? {
    guard let id = self.page?.asset.id else { return nil }
    let phase: DetailImageKey.Phase = switch self.state(of: id) {
    case .loading: .loading
    case .loaded: .loaded
    case .unavailable: .unavailable
    }
    let captureRequest = self.captureModel.detailID == id ? self.captureModel.detailRequest : nil
    return DetailImageKey(id: id, phase: phase, captureRequest: captureRequest)
  }

  private var title: Text {
    if let date = self.page?.asset.creationDate {
      Text(date, format: .dateTime.year().month().day().hour().minute())
    } else {
      Text("날짜 없음")
    }
  }
}

/// 상세 한 장: 창 안 이미지 상태(`CategoryModel.detailImages`)로 그린다. 없으면 아직 안 읽었거나 읽는 중이다.
private struct PhotoPageView: View {
  let model: CategoryModel
  let page: PhotoPage
  let isCurrent: Bool

  var body: some View {
    self.content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // 이미지는 장식이라, 장 하나를 요소 하나로 묶어 상태를 읽고 "이전/다음 사진" 동작을 단다.
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(self.accessibilityLabel)
      .accessibilityAddTraits(.isImage)
  }

  private var state: ImageLoadState {
    self.model.detailImages[self.page.asset.id] ?? .loading
  }

  @ViewBuilder
  private var content: some View {
    switch self.state {
    case .loading:
      // 원본을 읽는 동안 이미 읽힌 썸네일이 있으면 흐린 자리표시로 보인다. 썸네일을 새로 읽지는 않는다.
      if let thumbnail = self.model.thumbnails[self.page.asset.id]?.image {
        Image(decorative: thumbnail.cgImage, orientation: thumbnail.orientation)
          .resizable()
          .scaledToFit()
          .blur(radius: 12)
          .clipped()
      } else {
        SnapLoadingDots()
      }
    case let .loaded(image):
      VStack(spacing: 12) {
        ZoomableImageView(image: image, isCurrent: self.isCurrent)
        if image.isLocalFallback {
          // 확대 영역 밖(장 아래쪽)에 둔다.
          Label("iCloud 원본 대신 기기에 있는 작은 버전입니다", systemImage: "icloud")
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
      // 다시 시도는 두지 않는다. 다른 장으로 갔다 오거나 닫고 다시 열면 다시 읽는다.
      StatusMessageView("사진을 불러오지 못했습니다", systemImage: "exclamationmark.triangle")
    }
  }

  /// 화면에 보이는 문구와 같다(심볼은 읽지 않는다).
  private var accessibilityLabel: Text {
    switch self.state {
    case .loading:
      Text("불러오는 중")
    case let .loaded(image):
      if image.isLocalFallback {
        Text("사진, iCloud 원본 대신 기기에 있는 작은 버전입니다")
      } else {
        Text("사진")
      }
    case .unavailable(.inCloudOnly):
      Text("iCloud 에만 있는 사진입니다. 사진 앱에서 내려받으면 볼 수 있습니다.")
    case .unavailable(.notFound):
      Text("보관함에 없는 사진입니다")
    case .unavailable(.failed):
      Text("사진을 불러오지 못했습니다")
    }
  }
}

/// 캡처 행동 상세의 키. 장(위치)이 바뀌면 같은 사진이어도 새 요청으로 다시 시작한다.
private struct PageKey: Hashable {
  let index: Int
  let id: ImageAsset.ID?
}

/// 지금 장 이미지 읽기 단계. 바코드 인식 `.task(id:)` 의 키다.
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
