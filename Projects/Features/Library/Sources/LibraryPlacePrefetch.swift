import Foundation
import IndexingInterface
import TripPlaceInterface

/// 보관함 화면의 여행 장소 이름 미리 받기 회차를 돌린다 (docs/ARCHITECTURE.md §4 위치·지도 원칙 ①). `LibraryModel` 이 소유하고
/// 계기(인덱싱 진행률, 앱 복귀, 로캘 변경)를 넘긴다. 이 파일로 나눈 것은 LibraryModel 파일 길이 때문이다.
/// 앱이 뒤로 가면 도는 회차를 멈추고(뒤에서는 BG 작업이 같은 TripPlace 인스턴스로 회차를 돌린다) 캐시 쓰기 신호를 앞으로 올 때까지 모은다.
/// 회차 요청은 하나씩 차례로 처리하고, 도는 중 온 요청 여러 개는 끝난 뒤 한 회차로 합친다. 1단계(분류)를 마치기 전에 꺼낸 요청은 버린다
/// (1단계를 마칠 때의 진행률이 다시 요청한다). 2단계(글자 읽기)는 기다리지 않는다: 지오코딩은 간격을 둔 네트워크 요청 하나라
/// 기기 연산을 쓰는 글자 읽기와 거의 겹치지 않는다.
@MainActor
final class LibraryPlacePrefetch {
  /// 회차를 하라는 신호. `run` 이 도는 동안(보관함 화면 `.task` 수명)만 있다. 마지막 신호만 남긴다.
  private var requests: AsyncStream<Void>.Continuation?
  /// `run` 을 시작할 때마다 하나씩 올린다. 화면을 나갔다 바로 들어와 지난 루프가 늦게 깨어나도 신호를 넘기지 않게 한다.
  private var generation = 0
  /// 지금 도는 회차. 인덱싱이 다시 돌거나 로캘이 바뀌면 취소한다(진행 중 요청은 끝까지 가서 캐시에 쓴다).
  private var round: Task<Void, Never>?
  /// 마지막으로 받은 인덱싱 진행률이 1단계를 마쳤는지(`IndexingProgress.phase` 가 `.classifying` 이 아님). 요청을 꺼낼 때마다 본다.
  /// 인덱싱이 멈춰도 마지막 값을 두고, 화면 진입(`run`) 때 false 로 되돌린다(`LibraryModel.indexingProgress` 는 지난 값을 둔다).
  private var isClassified = false
  /// 앱이 앞에 있는지(scenePhase). 화면이 뒤에서 생기면 첫 값 `.background`(`sceneEnteredBackground`)로 거짓이 되고, 앞에서 켜면
  /// 첫 값이 `.inactive` 라 기본값 참을 쓴다(`.active` 는 변화로 온다. 미리 받기는 보관함 화면 진입이 첫 `.active` 뒤에 시작한다).
  private var isSceneActive = true
  /// 뒤에 있는 동안 캐시 쓰기가 있었는지. 앞으로 올 때 한 번 알리고 푼다.
  private var hasPendingPlaceChange = false

  private let tripPlace: (any TripPlaceClient)?
  private let locale: @Sendable () -> Locale

  /// - Parameters:
  ///   - tripPlace: 미리 받기. nil 이면(저장소를 열지 못함) 아무것도 하지 않는다.
  ///   - locale: 장소 이름의 로캘. 회차를 시작할 때 한 번 부른다.
  init(tripPlace: (any TripPlaceClient)?, locale: @escaping @Sendable () -> Locale) {
    self.tripPlace = tripPlace
    self.locale = locale
  }

  /// 캐시 쓰기 신호를 넘기고 회차 요청을 처리한다. 부른 Task 가 취소되면(화면이 사라짐) 도는 회차를 취소하고 끝난다.
  /// - Parameter placeChanged: 미리 받기가 장소 캐시에 썼다.
  func run(placeChanged: @escaping @MainActor @Sendable () -> Void) async {
    guard let tripPlace = self.tripPlace else { return }
    self.generation += 1
    let generation = self.generation
    // 화면을 나가면 도는 회차가 취소되므로, 다시 들어와 처음 오는 진행률이 1단계를 마쳤으면(글자 읽기 중 포함) 새로 계기가 되게 한다.
    self.isClassified = false
    let (requests, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.requests = continuation
    await withDiscardingTaskGroup { group in
      group.addTask {
        await self.forwardPlaceChanges(tripPlace, generation: generation, placeChanged: placeChanged)
      }
      group.addTask {
        await self.runRequests(requests, tripPlace: tripPlace, generation: generation)
      }
    }
    // 화면이 사라졌다. 이후 신호는 버리고, 다음 진입이 새 스트림을 만든다.
    if self.isCurrent(generation) {
      self.requests = nil
    }
  }

  /// 회차를 하나 요청한다. 화면이 사라져 루프가 끝났으면 버린다.
  func request() {
    self.requests?.yield()
  }

  /// 인덱싱 진행률을 받았다. 1단계를 막 마쳤거나(화면 진입 뒤 첫 진행률 포함) 1·2단계를 모두 마쳤으면 회차를 요청하고, 다시 분류하기 시작했으면(새 사진)
  /// 도는 회차를 멈춘다. 글자 읽기 중 배치마다 오는 진행률은 회차를 요청하지 않는다(그때마다 저장소를 다시 읽지 않게).
  func indexingProgressChanged(phase: IndexingProgress.Phase) {
    let wasClassified = self.isClassified
    self.isClassified = phase != .classifying
    if !self.isClassified {
      self.round?.cancel()
    } else if !wasClassified || phase == .finished {
      self.request()
    }
  }

  /// 기기 로캘이 바뀌었다. 도는 회차를 멈추고 새 로캘로 회차를 요청한다. 멈춘 회차의 진행 중 요청이 옛 로캘로 한 번 저장될 수 있고,
  /// 다음 회차가 새 로캘로 덮는다.
  func localeChanged() {
    self.round?.cancel()
    self.request()
  }

  /// 앱이 앞으로 왔다. 오프라인이던 동안 받지 못한 이름을 받도록 회차를 요청한다(1단계를 마치기 전이면 버린다).
  /// - Returns: 뒤에 있는 동안 캐시 쓰기가 있었는지. 참이면 받는 쪽이 장소를 읽는 화면을 한 번 다시 읽게 한다.
  func sceneBecameActive() -> Bool {
    self.isSceneActive = true
    defer { self.hasPendingPlaceChange = false }
    self.request()
    return self.hasPendingPlaceChange
  }

  /// 앱이 뒤로 갔다. 도는 회차만 멈춘다(진행 중 요청은 끝까지 간다). 요청 스트림과 1단계 여부는 그대로라 앞으로 올 때의 요청이 다시 회차를 연다.
  /// 그 뒤 캐시 쓰기 신호는 앞으로 올 때까지 모은다(뒤에서 화면들이 저장소를 읽지 않게).
  func sceneEnteredBackground() {
    self.isSceneActive = false
    self.round?.cancel()
  }

  // MARK: - Private

  private func forwardPlaceChanges(
    _ tripPlace: any TripPlaceClient,
    generation: Int,
    placeChanged: @MainActor () -> Void
  ) async {
    for await _ in await tripPlace.placeChanges() {
      guard self.isCurrent(generation) else { return }
      if self.isSceneActive {
        placeChanged()
      } else {
        self.hasPendingPlaceChange = true
      }
    }
  }

  private func runRequests(_ requests: AsyncStream<Void>, tripPlace: any TripPlaceClient, generation: Int) async {
    for await _ in requests {
      guard self.isCurrent(generation) else { return }
      guard self.isClassified else { continue }
      await self.runRound(tripPlace)
    }
  }

  /// 회차를 따로 된 Task 로 돌려 그 회차만 멈출 수 있게 한다. 기다리는 쪽이 취소되면(화면이 사라짐) 회차도 취소한다.
  private func runRound(_ tripPlace: any TripPlaceClient) async {
    let locale = self.locale()
    let round = Task { await tripPlace.prefetchPlaces(locale: locale) }
    self.round = round
    await withTaskCancellationHandler {
      await round.value
    } onCancel: {
      round.cancel()
    }
    if self.round == round {
      self.round = nil
    }
  }

  private func isCurrent(_ generation: Int) -> Bool {
    generation == self.generation
  }
}
