import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
import Testing
import WidgetKit
@testable import ExpiryWidgetFeature

/// 지금 시각은 Asia/Seoul 2026-10-26 15:00 으로 고정한다.
struct ExpiryWidgetProviderTests {
  @Test("저장소를 열지 못하면 '앱을 열어 주세요' 하나를 넣고 30분 뒤 다시 읽는다")
  func unavailableWhenStoreMissing() async {
    let timeline = await provider(store: nil).timeline()

    #expect(timeline.entries == [ExpiryWidgetEntry(date: now, content: .unavailable)])
    #expect(timeline.policy == .after(now.addingTimeInterval(30 * 60)))
  }

  @Test("저장소를 읽지 못해도 '앱을 열어 주세요'다")
  func unavailableWhenReadFails() async {
    let timeline = await provider(store: PhotoStoreClientFake(error: .failed)).timeline()

    #expect(timeline.entries == [ExpiryWidgetEntry(date: now, content: .unavailable)])
  }

  @Test("다시 읽기는 30분 뒤와 내일 시작 중 이른 때다")
  func unavailableRetryCapsAtTomorrow() async {
    let lateNight = Date.seoul(2026, 10, 26, hour: 23, minute: 50)

    let timeline = await provider(store: nil, now: lateNight).timeline()

    #expect(timeline.policy == .after(.seoul(2026, 10, 27, hour: 0)))
  }

  @Test("7일 안에 만료가 없으면 0개, 확인 중 아님")
  func emptySummary() async throws {
    let store = PhotoStoreClientFake(images: [.gifticon(id: "a", expiry: .date(2026, 11, 10))])

    let entry = try #require(await provider(store: store).timeline().entries.first)

    #expect(entry.content == .summary(ExpiryWidgetSummary(
      date: .date(2026, 10, 26),
      count: 0,
      nearestDaysLeft: nil,
      isChecking: false
    )))
  }

  @Test("임박: 개수와 가장 가까운 D-day")
  func upcomingSummary() async throws {
    let store = PhotoStoreClientFake(images: [
      .gifticon(id: "a", expiry: .date(2026, 10, 26)),
      .gifticon(id: "b", expiry: .date(2026, 11, 2)),
      .gifticon(id: "c", expiry: .date(2026, 11, 3)),
    ])

    let entry = try #require(await provider(store: store).timeline().entries.first)

    #expect(entry.content == .summary(ExpiryWidgetSummary(
      date: .date(2026, 10, 26),
      count: 2,
      nearestDaysLeft: 0,
      isChecking: false
    )))
  }

  @Test("추출 대기가 있으면 지금 값과 함께 확인 중")
  func checkingWhenExtractionPending() async throws {
    let store = PhotoStoreClientFake(images: [
      .gifticon(id: "a", expiry: .date(2026, 10, 28)),
      .pendingGifticon(id: "b"),
    ])

    let entry = try #require(await provider(store: store).timeline().entries.first)

    #expect(entry.content == .summary(ExpiryWidgetSummary(
      date: .date(2026, 10, 26),
      count: 1,
      nearestDaysLeft: 2,
      isChecking: true
    )))
  }

  @Test("사용함 표시한 기프티콘은 세지 않는다")
  func excludesUsed() async throws {
    let store = PhotoStoreClientFake(
      images: [.gifticon(id: "a", expiry: .date(2026, 10, 28)), .gifticon(id: "b", expiry: .date(2026, 10, 30))],
      usedIDs: ["a"]
    )

    let entry = try #require(await provider(store: store).timeline().entries.first)

    #expect(entry.content == .summary(ExpiryWidgetSummary(
      date: .date(2026, 10, 26),
      count: 1,
      nearestDaysLeft: 4,
      isChecking: false
    )))
  }

  @Test("entry 8개: 첫 것은 지금, 나머지는 각 날의 시작. 내일 시작에 다시 읽는다")
  func entriesStartAtEachDay() async {
    let store = PhotoStoreClientFake(images: [.gifticon(id: "a", expiry: .date(2026, 10, 27))])

    let timeline = await provider(store: store).timeline()

    #expect(timeline.entries.map(\.date) == [now] + (27 ... 31).map { Date.seoul(2026, 10, $0, hour: 0) } + [
      .seoul(2026, 11, 1, hour: 0), .seoul(2026, 11, 2, hour: 0),
    ])
    #expect(timeline.entries.map(\.content.count) == [1, 1, 0, 0, 0, 0, 0, 0])
    #expect(timeline.policy == .after(.seoul(2026, 10, 27, hour: 0)))
  }

  @Test("타임라인마다 저장소를 새로 연다")
  func opensStoreEveryTimeline() async {
    let opened = OpenCounter()
    let provider = ExpiryWidgetProvider(
      makeStore: {
        opened.increment()
        return PhotoStoreClientFake()
      },
      calendar: .seoul,
      now: { now }
    )

    _ = await provider.timeline()
    _ = await provider.timeline()

    #expect(opened.count == 2)
  }
}

private let now = Date.seoul(2026, 10, 26, hour: 15)

private func provider(store: PhotoStoreClientFake?, now: Date = now) -> ExpiryWidgetProvider {
  ExpiryWidgetProvider(makeStore: { store }, calendar: .seoul, now: { now })
}

private final class OpenCounter: Sendable {
  private let value = Mutex(0)

  var count: Int {
    self.value.withLock { $0 }
  }

  func increment() {
    self.value.withLock { $0 += 1 }
  }
}

private extension ExpiryWidgetEntry.Content {
  /// 요약의 개수. `.unavailable` 이면 nil.
  var count: Int? {
    guard case let .summary(summary) = self else { return nil }
    return summary.count
  }
}

private extension IndexedImage {
  /// 글자를 읽고 추출한 기프티콘.
  static func gifticon(id: String, expiry: LocalDate) -> IndexedImage {
    IndexedImage(
      asset: .widgetStub(id: id),
      labels: [],
      textRecognition: .recognized([]),
      categories: [.gifticon],
      gifticon: GifticonInfo(expiryDate: expiry, redemptionPlace: nil)
    )
  }

  /// 글자를 읽었지만 아직 추출하지 않은 기프티콘(추출 대기).
  static func pendingGifticon(id: String) -> IndexedImage {
    IndexedImage(asset: .widgetStub(id: id), labels: [], textRecognition: .recognized([]), categories: [.gifticon])
  }
}

private extension ImageAsset {
  static func widgetStub(id: String) -> ImageAsset {
    ImageAsset(id: id, creationDate: nil, coordinate: nil, pixelWidth: 1, pixelHeight: 1, isScreenshot: false)
  }
}

private extension LocalDate {
  static func date(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)!
  }
}

private extension Calendar {
  static let seoul: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
  }()
}

private extension Date {
  static func seoul(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int = 0) -> Date {
    Calendar.seoul.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }
}
