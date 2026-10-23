import Core
import Foundation
import Observation
import PhotoStoreInterface

/// 영수증 목록 화면의 상태와 로직 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 카테고리 화면에서 영수증 줄을 열면 격자 대신 이 목록을 보인다. 목록 화면은 한 번에 하나만 열리므로 App 이 하나를 소유한다.
/// 묶기(월별/가게별)는 저장하지 않는 화면 일시 상태라 View 가 갖고, 섹션·합계는 View 가 이 Model 의
/// `content`·`calendar` 로 Core `ReceiptListSections.sections` 를 불러 만든다.
/// 저장소 변경·날짜 변경 신호는 LibraryView 가 `libraryStoreChanged()`·`dayChanged()` 로 넘긴다(Model 끼리 참조하지 않는다).
/// 목록 항목에는 사진에서 읽은 가게·금액이 들어 있으므로 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
@MainActor
@Observable
public final class ReceiptListModel {
  /// 목록 내용. 화면을 다시 열거나 상세에서 돌아오면 지난 목록을 둔 채 다시 읽는다.
  public private(set) var content: ReceiptListContent = .loading
  /// 월 섹션·날짜 표시가 쓰는 기기 달력. `.autoupdatingCurrent` 를 그대로 두면 시간대가 바뀌어도 상태가 같아 다시 그려지지 않으므로,
  /// 읽을 때와 `dayChanged()` 때 기기 달력의 사본(달력 체계·시간대·로캘)을 담는다.
  public private(set) var calendar: Calendar

  /// `onAppear()` 를 시작할 때마다 하나씩 올린다. 화면을 닫았다 바로 열면 지난 Task 가 늦게 깨어날 수 있으므로,
  /// 내용은 지금 번호의 Task 만 바꾼다.
  @ObservationIgnored private var generation = 0
  /// 다시 읽으라는 신호. 화면이 열려 있는 동안(`onAppear()` 가 구독하는 동안)만 있다.
  /// 상세가 열려 있는 동안은 목록 화면의 `.task` 도 끝나 없다. 그동안 온 신호는 버리고, 돌아오면 한 번 다시 읽는다.
  @ObservationIgnored private var reloadRequests: AsyncStream<Void>.Continuation?

  @ObservationIgnored private let photoStore: (any PhotoStoreClient)?
  @ObservationIgnored private let currentCalendar: @Sendable () -> Calendar

  /// - Parameters:
  ///   - photoStore: 분류 결과 저장소. App 이 저장소를 열지 못하면 nil 이다(그때는 영수증 줄이 없어 이 화면에 오지 않는다).
  ///   - calendar: 기기 달력. 읽을 때와 `dayChanged()` 때 부른다.
  public init(
    photoStore: (any PhotoStoreClient)?,
    calendar: @escaping @Sendable () -> Calendar = { .current }
  ) {
    self.photoStore = photoStore
    self.currentCalendar = calendar
    self.calendar = calendar()
  }

  // MARK: - Events

  /// 목록을 읽고, 화면이 열려 있는 동안(View 의 `.task` 수명) 다시 읽기 신호를 기다린다.
  /// 다시 읽기는 한 번에 하나씩 차례로 하고, 도는 중 들어온 신호 여러 개는 끝난 뒤 한 번으로 합친다.
  public func onAppear() async {
    self.generation += 1
    let generation = self.generation
    if self.content == .failed {
      self.content = .loading
    }
    guard let photoStore = self.photoStore else {
      self.content = .failed
      return
    }
    let (requests, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.reloadRequests = continuation
    // 처음 읽기.
    continuation.yield()
    for await _ in requests {
      guard self.isCurrent(generation) else { return }
      await self.reload(photoStore: photoStore, generation: generation)
    }
    // 화면이 닫혔다. 이후 신호와 다시 시도는 버리고, 다음 진입이 처음 읽기를 한다.
    if self.isCurrent(generation) {
      self.reloadRequests = nil
    }
  }

  /// 저장소 내용(분류·추출 값)이 바뀌었을 수 있다는 신호. 화면이 닫혀 있으면 버린다.
  public func libraryStoreChanged() {
    self.reloadRequests?.yield()
  }

  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했을 때만, 화면이 열려 있으면 다시 읽는다.
  public func retryButtonTapped() {
    guard self.content == .failed, let reloadRequests = self.reloadRequests else { return }
    self.content = .loading
    reloadRequests.yield()
  }

  /// 날짜나 시간대가 바뀌었다(자정을 넘김, 시간대 변경, 앱 복귀). 저장소는 읽지 않고 달력만 다시 담는다.
  /// 화면이 닫혀 있어도 담아, 다음에 열 때 지난 시간대로 월을 나누지 않는다.
  public func dayChanged() {
    self.refreshCalendar()
  }

  // MARK: - Private

  /// 저장소 호출은 취소되지 않으므로, 돌아온 뒤 화면이 닫혔거나 다른 진입이 시작됐으면 결과를 버린다.
  /// 다시 읽기에 실패하면 지난 목록을 둔다(저장소 문제는 보관함 화면의 인덱싱 멈춤 안내가 알린다).
  private func reload(photoStore: any PhotoStoreClient, generation: Int) async {
    self.refreshCalendar()
    let items: [ReceiptListItem]
    do throws(PhotoStoreError) {
      items = try await photoStore.receipts()
    } catch {
      guard self.isCurrent(generation), !Task.isCancelled else { return }
      if case .loaded = self.content {
        return
      }
      self.content = .failed
      return
    }
    guard self.isCurrent(generation), !Task.isCancelled else { return }
    // 진행률 대부분은 영수증을 바꾸지 않으므로, 같으면 대입하지 않아 다시 그리지 않는다.
    guard self.content != .loaded(items) else { return }
    self.content = .loaded(items)
  }

  /// 같으면 대입하지 않아 다시 그리지 않는다.
  private func refreshCalendar() {
    let calendar = self.currentCalendar()
    if self.calendar != calendar {
      self.calendar = calendar
    }
  }

  private func isCurrent(_ generation: Int) -> Bool {
    generation == self.generation
  }
}

/// 영수증 목록 내용.
public enum ReceiptListContent: Equatable {
  case loading
  /// 빈 배열이면 영수증이 없다. 최신순(저장소 `receipts()` 순서)이다.
  case loaded([ReceiptListItem])
  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했다. 이미 목록이 있을 때 실패하면 지난 목록을 둔다.
  case failed
}
