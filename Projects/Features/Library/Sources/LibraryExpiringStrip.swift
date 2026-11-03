import Core
import Foundation
import Observation
import PhotoStoreInterface

/// 보관함 홈 "곧 만료" 띠의 값 (docs/ARCHITECTURE.md §4 카테고리 화면). `LibraryModel` 이 소유하고 계기(화면 진입, 인덱싱 진행률·멈춤,
/// 기프티콘 사용 여부 변경, 앱 복귀)마다 저장소 `gifticons()` 를 다시 읽고, 날짜·시간대 변경은 지난 읽기로 오늘만 다시 계산한다.
/// 읽기 요청은 하나씩 차례로 처리하고, 읽는 중 들어온 요청 여러 개는 끝난 뒤 한 번으로 합친다(요청은 "지금 상태로 다시 읽어라"라서 합쳐도 된다).
/// 읽기 루프(`begin`·`run`·`end`)는 화면 진입 Task 가 취소되거나 화면 진입의 다른 일이 모두 끝나면 끝난다. 저장소가 없으면 시작하지 않는다.
@MainActor
@Observable
final class LibraryExpiringStrip {
  /// 띠 값. 아직 첫 읽기 전이거나 처음부터 읽지 못했거나 저장소가 없으면 nil(띠를 숨긴다).
  /// 다시 읽기에 실패하면 지난 값을 둔다. 같은 값이면 대입하지 않아 진행률마다 홈을 다시 그리지 않는다.
  private(set) var current: ExpiringGifticons?

  /// 마지막으로 읽은 `gifticons()` 결과 전체(오늘로 거르지 않은 것). 날짜 변경 때 다시 읽지 않고 다시 계산하는 데 쓴다.
  @ObservationIgnored private var source: [GifticonListItem]?
  /// 다시 읽으라는 신호. `begin()` 이 만들고 `run` 이 도는 동안만 있다(끝나면 nil).
  @ObservationIgnored private var requests: AsyncStream<Void>.Continuation?
  /// `begin()` 할 때마다 하나씩 올린다. 화면을 나갔다 바로 들어와 지난 읽기가 늦게 끝나도 값을 바꾸지 않게 한다.
  @ObservationIgnored private var generation = 0

  @ObservationIgnored private let photoStore: (any PhotoStoreClient)?
  @ObservationIgnored private let calendar: Calendar
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private let limit: Int

  /// 매개변수 뜻은 `LibraryModel.init` 과 같다. `limit` 은 칩 수 상한(`LibraryModel.expiringLimit`).
  init(photoStore: (any PhotoStoreClient)?, calendar: Calendar, now: @escaping @Sendable () -> Date, limit: Int) {
    self.photoStore = photoStore
    self.calendar = calendar
    self.now = now
    self.limit = limit
  }

  /// 새 세대를 시작한다. `LibraryModel.onAppear()` 가 그룹을 열기 전에 동기로 불러, 자식 Task 가 어떤 순서로 시작해도
  /// 첫 진행률의 `request()` 가 통로를 찾게 한다. 지난 통로는 닫고, 새 통로에 화면 진입 읽기 신호를 넣어 둔다.
  /// 저장소가 없으면 통로를 두지 않고 끝난 빈 스트림을 돌려준다(`run` 이 바로 끝난다).
  func begin() -> (requests: AsyncStream<Void>, generation: Int) {
    self.generation += 1
    self.requests?.finish()
    self.requests = nil
    guard self.photoStore != nil else {
      let (requests, continuation) = AsyncStream.makeStream(of: Void.self)
      continuation.finish()
      return (requests, self.generation)
    }
    let (requests, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.requests = continuation
    // 화면 진입 읽기.
    continuation.yield()
    return (requests, self.generation)
  }

  /// 요청마다 읽는다. 부른 Task 가 취소되거나(화면이 사라짐) `end(generation:)` 가 통로를 닫으면(화면 진입의 다른 일이 모두 끝남)
  /// 남은 신호를 읽은 뒤 끝나고, 자기 세대면 통로를 치운다.
  func run(_ requests: AsyncStream<Void>, generation: Int) async {
    guard let photoStore = self.photoStore else { return }
    for await _ in requests {
      guard generation == self.generation else { return }
      await self.read(photoStore: photoStore, generation: generation)
    }
    guard generation == self.generation else { return }
    self.requests = nil
  }

  /// 화면 진입의 다른 일이 모두 끝났다. 자기 세대면 통로를 닫는다. 읽는 중인 읽기는 취소하지 않고,
  /// 버퍼에 남은 신호(최대 1개, 화면 진입 신호 포함)는 `run` 이 읽은 뒤 끝난다.
  func end(generation: Int) {
    guard generation == self.generation else { return }
    self.requests?.finish()
    self.requests = nil
  }

  /// 읽기 루프가 끝났으면(화면을 떠남, 또는 화면 진입의 다른 일이 모두 끝남) 신호는 버려지고, 다음 화면 진입이 읽는다.
  func request() {
    self.requests?.yield()
  }

  /// 오늘이 바뀌었을 수 있다. 저장소를 다시 읽지 않고 지난 읽기로 다시 계산한다(실패 경로가 없다). 읽은 적이 없으면 할 일이 없다.
  func dayChanged() {
    self.recompute()
  }

  /// 읽지 못하면 아무것도 바꾸지 않는다(처음이면 숨김 그대로, 아니면 지난 값). 저장소 실패는 보관함 멈춤 안내가 알린다.
  private func read(photoStore: any PhotoStoreClient, generation: Int) async {
    let items: [GifticonListItem]
    do throws(PhotoStoreError) {
      items = try await photoStore.gifticons()
    } catch {
      return
    }
    guard generation == self.generation else { return }
    self.source = items
    self.recompute()
  }

  /// 오늘은 계산할 때마다 `now()` 로 다시 읽는다. 그래서 읽기가 끝날 때도 오늘이 맞춰진다.
  private func recompute() {
    guard let source = self.source else { return }
    let strip = ExpiringGifticons.make(
      from: source, today: LocalDate(self.now(), calendar: self.calendar), limit: self.limit
    )
    if self.current != strip {
      self.current = strip
    }
  }
}
