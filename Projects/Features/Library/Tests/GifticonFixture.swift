import Core
import Foundation
import ImageAnalysisTesting
import MapTesting
import PasteboardTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
@testable import LibraryFeature

/// 기프티콘 목록·상세 테스트의 공통 준비. 지금 시각은 Asia/Seoul 2026-10-19 08:00 으로 고정한다(`ReminderFixture` 와 같다).
@MainActor
enum GifticonFixture {
  static let now = Date.seoul(2026, 10, 19, hour: 8)

  static func listModel(
    photoStore: PhotoStoreClientFake?,
    clock: TestClock = TestClock(now: GifticonFixture.now, calendar: .seoul)
  ) -> GifticonListModel {
    GifticonListModel(photoStore: photoStore, calendar: { clock.calendar }, now: { clock.now })
  }

  static func captureModel(
    photoStore: PhotoStoreClientFake?,
    imageAnalysis: ImageAnalysisClientFake = ImageAnalysisClientFake(),
    map: MapClientFake = MapClientFake(),
    pasteboard: PasteboardClientFake = PasteboardClientFake(),
    clock: TestClock = TestClock(now: GifticonFixture.now, calendar: .seoul)
  ) -> CaptureActionsModel {
    CaptureActionsModel(
      photoStore: photoStore,
      imageAnalysis: imageAnalysis,
      map: map,
      pasteboard: pasteboard,
      calendar: { clock.calendar },
      now: { clock.now }
    )
  }
}

/// 테스트가 바꿀 수 있는 지금 시각과 기기 달력. Model 이 부르는 클로저가 읽는다.
final class TestClock: Sendable {
  private struct State {
    var now: Date
    var calendar: Calendar
  }

  private let state: Mutex<State>

  init(now: Date, calendar: Calendar) {
    self.state = Mutex(State(now: now, calendar: calendar))
  }

  var now: Date {
    get { self.state.withLock { $0.now } }
    set { self.state.withLock { $0.now = newValue } }
  }

  var calendar: Calendar {
    get { self.state.withLock { $0.calendar } }
    set { self.state.withLock { $0.calendar = newValue } }
  }
}

extension IndexedImage {
  /// 글자를 읽고 추출한 기프티콘. 생성일·교환처·보강 상태를 정할 수 있다.
  static func gifticon(
    id: String,
    creationDate: Date? = nil,
    expiryDate: LocalDate?,
    place: String? = nil,
    modelFilledFields: Set<GifticonInfo.Field> = [],
    modelFill: GifticonModelFill = .done,
    lines: [RecognizedTextLine] = []
  ) -> IndexedImage {
    IndexedImage(
      asset: .stub(id: id, creationDate: creationDate),
      labels: [],
      textRecognition: .recognized(lines),
      categories: [.gifticon],
      gifticon: GifticonInfo(expiryDate: expiryDate, redemptionPlace: place, modelFilledFields: modelFilledFields),
      gifticonModelFill: modelFill
    )
  }

  /// 글자를 아직 읽지 않은 기프티콘(목록의 "확인 중").
  static func pendingGifticon(id: String) -> IndexedImage {
    IndexedImage(asset: .stub(id: id), labels: [], textRecognition: .pending, categories: [.gifticon])
  }

  /// 글자를 읽은 캡처(기프티콘 아님).
  static func capture(id: String, lines: [String], categories: Set<ImageCategory> = [.shopping]) -> IndexedImage {
    IndexedImage(
      asset: .stub(id: id),
      labels: [],
      textRecognition: .recognized(lines.map(RecognizedTextLine.stub)),
      categories: categories
    )
  }
}

extension RecognizedTextLine {
  static func stub(_ text: String) -> RecognizedTextLine {
    RecognizedTextLine(text: text, confidence: 1, boundingBox: .zero)
  }
}

extension GifticonListContent {
  /// 읽은 항목의 식별자. 읽기 전이나 실패면 nil.
  var ids: [ImageAsset.ID]? {
    guard case let .loaded(items) = self else { return nil }
    return items.map(\.id)
  }

  var items: [GifticonListItem]? {
    guard case let .loaded(items) = self else { return nil }
    return items
  }
}

extension Calendar {
  static let losAngeles: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
  }()
}
