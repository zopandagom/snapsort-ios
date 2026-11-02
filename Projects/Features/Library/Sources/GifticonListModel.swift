import Core
import Foundation
import Observation
import PhotoStoreInterface

/// 기프티콘 목록 화면의 상태와 로직 (docs/ARCHITECTURE.md §4 카테고리 화면).
/// 보관함에서 기프티콘 카드를 열면 카테고리 격자 대신 이 목록을 보인다. 목록 화면은 한 번에 하나만 열리므로 App 이 하나를 소유한다.
/// 탭(미사용/사용함)·정렬(만료 임박순/월별)은 저장하지 않는 화면 일시 상태라 View 가 갖고, 섹션은 View 가 이 Model 의
/// `content`·`today`·`calendar` 로 Core `GifticonListSections.sections` 를 불러 만든다.
/// 저장소 변경·날짜 변경 신호는 LibraryView 가 `libraryStoreChanged()`·`dayChanged()` 로 넘긴다(Model 끼리 참조하지 않는다).
/// 줄의 "사용함"·"미사용으로" 버튼이나 줄 밀기로 사용 여부를 바꿀 수 있다(`usageToggled(id:toUsed:)`). 쓰기에 성공하면 `usageRevision` 이 오르고 LibraryView 가
/// 알림 동기화·
/// 다른 화면 다시 읽기로 넘긴다. 이 목록은 쓰기가 끝나면 스스로 다시 읽는다.
@MainActor
@Observable
public final class GifticonListModel {
  /// 목록 내용. 화면을 다시 열거나 상세에서 돌아오면 지난 목록을 둔 채 다시 읽는다.
  public private(set) var content: GifticonListContent = .loading
  /// 섹션·D-n 의 기준. 기기 시간대의 오늘.
  public private(set) var today: LocalDate
  /// 월 섹션·만료일 표시가 쓰는 기기 달력. `.autoupdatingCurrent` 를 그대로 두면 시간대가 바뀌어도 상태가 같아 다시 그려지지 않으므로,
  /// 읽을 때와 `dayChanged()` 때 기기 달력의 사본(달력 체계·시간대·로캘)을 담는다.
  public private(set) var calendar: Calendar
  /// 사용 여부를 쓰는 중인 줄. View 는 그 줄의 밀기 단추를 숨기고 줄 버튼을 막아 두 번 쓰지 않는다. 다른 줄은 함께 쓸 수 있다.
  /// 화면을 닫아도 쓰기가 끝날 때까지 남는다.
  public private(set) var updatingUsageIDs: Set<ImageAsset.ID> = []
  /// 쓰기에 성공할 때마다(화면을 닫은 뒤라도) 오른다. LibraryView 가 알림 동기화·정리 화면·상세 다시 읽기로 넘기고, View 는 성공 햅틱에 쓴다.
  public private(set) var usageRevision = 0
  /// 줄별 마지막 성공한 쓰기. 성공할 때 `content` 와 같은 턴에 그 줄의 항목을 덮어쓴다(지우지 않는다. 키는 기프티콘 수로 묶인다).
  /// View 가 이 화면이 생긴 뒤의 변경(`sequence` > 화면이 생길 때의 `usageRevision`)에만 도장·줄 빠짐을 건다. 실패면 바뀌지 않는다.
  public private(set) var usageChanges: [ImageAsset.ID: GifticonUsageChange] = [:]
  public private(set) var alert: GifticonListAlert?

  /// `onAppear()` 를 시작할 때마다 하나씩 올린다. 화면을 닫았다 바로 열면 지난 Task 가 늦게 깨어날 수 있으므로,
  /// 내용은 지금 번호의 Task 만 바꾼다.
  @ObservationIgnored private var generation = 0
  /// 다시 읽으라는 신호. 화면이 열려 있는 동안(`onAppear()` 가 구독하는 동안)만 있다.
  /// 상세가 열려 있는 동안은 목록 화면의 `.task` 도 끝나 없다. 그동안 온 신호는 버리고, 돌아오면 한 번 다시 읽는다.
  @ObservationIgnored private var reloadRequests: AsyncStream<Void>.Continuation?
  /// 쓰기를 시작할 때마다 오른다. 다시 읽는 동안 쓰기가 시작돼 끝났는지 가린다.
  @ObservationIgnored private var usageWriteCount = 0

  @ObservationIgnored private let photoStore: (any PhotoStoreClient)?
  @ObservationIgnored private let currentCalendar: @Sendable () -> Calendar
  @ObservationIgnored private let now: @Sendable () -> Date

  /// - Parameters:
  ///   - photoStore: 분류 결과 저장소. App 이 저장소를 열지 못하면 nil 이다(그때는 기프티콘 카드가 없어 이 화면에 오지 않는다).
  ///   - calendar: 기기 달력. 읽을 때와 `dayChanged()` 때 부른다.
  ///   - now: 지금 시각. 읽을 때와 `dayChanged()` 때 부른다.
  public init(
    photoStore: (any PhotoStoreClient)?,
    calendar: @escaping @Sendable () -> Calendar = { .current },
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.photoStore = photoStore
    self.currentCalendar = calendar
    self.now = now
    let current = calendar()
    self.calendar = current
    self.today = LocalDate(now(), calendar: current)
  }

  // MARK: - Events

  /// 목록을 읽고, 화면이 열려 있는 동안(View 의 `.task` 수명) 다시 읽기 신호를 기다린다.
  /// 다시 읽기는 한 번에 하나씩 차례로 하고, 도는 중 들어온 신호 여러 개는 끝난 뒤 한 번으로 합친다.
  public func onAppear() async {
    self.generation += 1
    let generation = self.generation
    self.alert = nil
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

  /// 저장소 내용(추출 값·사용 여부)이 바뀌었을 수 있다는 신호. 화면이 닫혀 있으면 버린다.
  public func libraryStoreChanged() {
    self.reloadRequests?.yield()
  }

  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했을 때만, 화면이 열려 있으면 다시 읽는다.
  public func retryButtonTapped() {
    guard self.content == .failed, let reloadRequests = self.reloadRequests else { return }
    self.content = .loading
    reloadRequests.yield()
  }

  /// 줄의 버튼을 누르거나 줄을 밀어 사용 여부를 `isUsed` 로 바꾸라고 했다. 이미 그 값이거나 그 줄을 쓰는 중이면 쓰지 않는다(머무는 줄을 다시 눌러도 되돌아가지 않는다).
  /// 쓰기는 화면을 닫아도 끝까지 하고, 성공하면 닫혔어도 `usageRevision` 을 올린다. 실패 알림은 같은 화면이 열려 있을 때만 띄운다.
  /// 결과와 상관없이 끝나면 다시 읽어 저장소 값과 맞춘다(쓰는 동안 버린 다시 읽기를 메운다).
  public func usageToggled(id: ImageAsset.ID, toUsed isUsed: Bool) async {
    guard let photoStore = self.photoStore, case let .loaded(items) = self.content,
          let item = items.first(where: { $0.id == id }), item.isUsed != isUsed,
          !self.updatingUsageIDs.contains(id)
    else { return }
    let generation = self.generation
    self.updatingUsageIDs.insert(id)
    self.usageWriteCount += 1
    do throws(PhotoStoreError) {
      if try await photoStore.setGifticonUsed(isUsed, id: id) {
        self.usageRevision += 1
        if case let .loaded(current) = self.content {
          self.content = .loaded(current.map { $0.id == id ? $0.with(isUsed: isUsed) : $0 })
        }
        self.usageChanges[id] = GifticonUsageChange(id: id, isUsed: isUsed, sequence: self.usageRevision)
      }
      // false 면 그사이 기프티콘이 아니게 됐다. 번호는 올리지 않고 아래 다시 읽기가 줄을 거둔다.
    } catch {
      if self.isCurrent(generation), self.reloadRequests != nil {
        self.alert = .usageUpdateFailed
      }
    }
    self.updatingUsageIDs.remove(id)
    self.reloadRequests?.yield()
  }

  public func alertDismissed() {
    self.alert = nil
  }

  /// 날짜나 시간대가 바뀌었다(자정을 넘김, 시간대 변경, 앱 복귀). 저장소는 읽지 않고 오늘과 달력만 다시 계산한다.
  /// 화면이 닫혀 있어도 계산해, 다음에 열 때 지난 날짜로 그리지 않는다.
  public func dayChanged() {
    self.refreshDay()
  }

  // MARK: - Private

  /// 저장소 호출은 취소되지 않으므로, 돌아온 뒤 화면이 닫혔거나 다른 진입이 시작됐으면 결과를 버린다.
  /// 다시 읽기에 실패하면 지난 목록을 둔다(저장소 문제는 보관함 화면의 인덱싱 멈춤 안내가 알린다).
  /// 사용 여부를 쓰는 중이면 읽은 결과를 버린다(쓰기 끝의 다시 읽기가 메운다). 읽는 동안 쓰기가 시작돼 끝났으면 쓴 값을 되돌리지 않게 한 번 더 읽는다.
  private func reload(photoStore: any PhotoStoreClient, generation: Int) async {
    while true {
      self.refreshDay()
      let writeCount = self.usageWriteCount
      let items: [GifticonListItem]
      do throws(PhotoStoreError) {
        items = try await photoStore.gifticons()
      } catch {
        guard self.isCurrent(generation), !Task.isCancelled else { return }
        if case .loaded = self.content {
          return
        }
        self.content = .failed
        return
      }
      guard self.isCurrent(generation), !Task.isCancelled else { return }
      guard self.updatingUsageIDs.isEmpty else { return }
      guard writeCount == self.usageWriteCount else { continue }
      // 진행률 대부분은 기프티콘을 바꾸지 않으므로, 같으면 대입하지 않아 다시 그리지 않는다.
      guard self.content != .loaded(items) else { return }
      self.content = .loaded(items)
      return
    }
  }

  /// 같으면 대입하지 않아 다시 그리지 않는다.
  private func refreshDay() {
    let calendar = self.currentCalendar()
    let today = LocalDate(self.now(), calendar: calendar)
    if self.calendar != calendar {
      self.calendar = calendar
    }
    if self.today != today {
      self.today = today
    }
  }

  private func isCurrent(_ generation: Int) -> Bool {
    generation == self.generation
  }
}

/// 기프티콘 목록 내용.
public enum GifticonListContent: Equatable {
  case loading
  /// 빈 배열이면 기프티콘이 없다. 최신순(저장소 `gifticons()` 순서)이다.
  case loaded([GifticonListItem])
  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했다. 이미 목록이 있을 때 실패하면 지난 목록을 둔다.
  case failed
}

/// 목록 줄 버튼·줄 밀기로 성공한 사용 여부 쓰기 한 번. `sequence` 는 그때의 `GifticonListModel.usageRevision` 이다.
public struct GifticonUsageChange: Equatable, Sendable {
  public let id: ImageAsset.ID
  public let isUsed: Bool
  public let sequence: Int
}

/// 기프티콘 목록 알림.
public enum GifticonListAlert: Hashable, Identifiable {
  /// 사용 여부를 저장하지 못했다.
  case usageUpdateFailed

  public var id: Self { self }
}

/// 기프티콘 목록의 탭. View 의 화면 일시 상태다(저장하지 않는다).
public enum GifticonTab: Hashable, CaseIterable {
  case unused
  case used
}
