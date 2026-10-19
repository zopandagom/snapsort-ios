import Core
import Foundation
import IndexingTesting
import NotificationInterface
import NotificationTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
@testable import LibraryFeature

/// 만료 알림 테스트의 공통 준비. 지금 시각은 Asia/Seoul 2026-10-19 08:00 으로 고정한다(오늘 09:00 알림이 아직 지나지 않았다).
@MainActor
enum ReminderFixture {
  /// 2026-10-29 만료 한 장의 7일 전·1일 전 알림 식별자.
  static let expectedIDsFor1029 = ["expiry.v1.gregorian.20261022.0.1", "expiry.v1.gregorian.20261028.1.0"]

  static func model(
    photoStore: PhotoStoreClientFake,
    notification: NotificationClientFake,
    indexing: IndexingClientFake? = nil,
    now: Date = .seoul(2026, 10, 19, hour: 8)
  ) -> LibraryModel {
    LibraryModel(
      photoLibrary: PhotoLibraryClientFake(currentState: .authorized),
      indexing: indexing,
      photoStore: photoStore,
      notification: notification,
      calendar: .seoul,
      now: { now }
    )
  }

  static func request(id: String) -> NotificationRequest {
    NotificationRequest(id: id, title: "", body: "", date: .date(2026, 11, 1), hour: 9, minute: 0)
  }
}

/// 호출 번호마다 따로 여는 문. 붙잡기로 한 번호의 호출은 열 때까지 기다리고, 나머지는 바로 지나간다.
/// 어느 번호가 들어왔는지 기록해, 테스트가 그 호출이 붙잡힌 뒤에 다음 단계로 가게 한다. 번호마다 한 호출만 붙잡는다.
/// 기본은 Task 가 취소되면 붙잡힌 호출이 풀린다. `ignoresCancellation` 이면 취소에도 `open` 까지 기다려,
/// 알림 센터 API 가 취소에 반응하지 않는 경우를 흉내 낸다. 이때 테스트는 끝나기 전에 반드시 연다(`defer { gates.open(_:) }`).
final class CallGates: Sendable {
  private struct State {
    var entered: Set<Int> = []
    var opened: Set<Int> = []
    var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
  }

  private let held: Set<Int>
  private let ignoresCancellation: Bool
  private let state = Mutex(State())
  private let streams: [Int: (stream: AsyncStream<Void>, continuation: AsyncStream<Void>.Continuation)]

  init(holding indices: Set<Int>, ignoresCancellation: Bool = false) {
    self.held = indices
    self.ignoresCancellation = ignoresCancellation
    self.streams = Dictionary(uniqueKeysWithValues: indices.map { ($0, AsyncStream.makeStream(of: Void.self)) })
  }

  func pass(_ index: Int) async {
    guard self.ignoresCancellation else {
      self.state.withLock { _ = $0.entered.insert(index) }
      guard let gate = self.streams[index] else { return }
      for await _ in gate.stream {}
      return
    }
    await withCheckedContinuation { continuation in
      // 열렸는지 확인과 대기 등록을 한 잠금 안에서 해, 그 사이에 연 것을 놓치지 않는다.
      let passes = self.state.withLock { state in
        state.entered.insert(index)
        guard self.held.contains(index), !state.opened.contains(index) else { return true }
        state.waiters[index] = continuation
        return false
      }
      if passes {
        continuation.resume()
      }
    }
  }

  func hasEntered(_ index: Int) -> Bool {
    self.state.withLock { $0.entered.contains(index) }
  }

  /// 여러 번 불러도 붙잡힌 호출은 한 번만 깨운다. 들어오기 전에 열면 그 호출은 바로 지나간다.
  func open(_ index: Int) {
    let waiter = self.state.withLock { state in
      state.opened.insert(index)
      return state.waiters.removeValue(forKey: index)
    }
    waiter?.resume()
    self.streams[index]?.continuation.finish()
  }
}

/// 훅이 몇 번째로 불렸는지 센다(0부터). 같은 훅의 두 번째 호출은 붙잡지 않게 문의 다른 번호로 넘기는 데 쓴다.
final class CallCounter: Sendable {
  private let count = Mutex(0)

  func next() -> Int {
    self.count.withLock { count in
      defer { count += 1 }
      return count
    }
  }
}

/// 기다릴 상태 변화가 없을 때(아무것도 하지 않았음을 확인할 때) 진행 중인 동기화가 끝나도록 충분히 양보한다.
@MainActor
func settle() async {
  for _ in 0 ..< 100 {
    await Task.yield()
  }
}

extension IndexedImage {
  /// 글자를 읽고 추출한 기프티콘. `expiryDate` 가 nil 이면 만료일을 찾지 못한 것이다.
  static func extractedGifticon(id: String, expiryDate: LocalDate?) -> IndexedImage {
    IndexedImage(
      asset: .stub(id: id),
      labels: [],
      textRecognition: .recognized([]),
      categories: [.gifticon],
      gifticon: GifticonInfo(expiryDate: expiryDate, redemptionPlace: nil)
    )
  }
}

extension LocalDate {
  static func date(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)!
  }
}

extension Calendar {
  static let seoul: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
  }()
}

extension Date {
  static func seoul(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int = 0) -> Date {
    Calendar.seoul.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }
}
