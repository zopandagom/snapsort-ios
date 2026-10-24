import Core
import Foundation
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Synchronization
@testable import LibraryFeature

/// 검색 Model 이 대기·색인 만들기·대조를 부른 기록. 지어낸 검색어만 담는다.
final class SearchProbe: Sendable {
  private struct State {
    var waits: [Duration] = []
    var matches: [String] = []
    var builds = 0
  }

  private let state = Mutex(State())

  var waits: [Duration] {
    self.state.withLock { $0.waits }
  }

  /// 대조를 시작한 검색어, 부른 순서.
  var matches: [String] {
    self.state.withLock { $0.matches }
  }

  var builds: Int {
    self.state.withLock { $0.builds }
  }

  func waited(_ duration: Duration) {
    self.state.withLock { $0.waits.append(duration) }
  }

  func matched(_ query: String) {
    self.state.withLock { $0.matches.append(query) }
  }

  func built() {
    self.state.withLock { $0.builds += 1 }
  }
}

/// 검색 테스트의 공통 준비. 기기는 Asia/Seoul·ko_KR 이고, 대기는 바로 돌아온다(`waitGates` 로 붙잡을 수 있다).
/// 붙잡는 단계마다 호출 번호(0부터)별로 문을 둔다. 대조·색인 문은 취소해도 풀리지 않아(`ignoresCancellation`) 늦은 결과를 흉내 낸다.
@MainActor
enum SearchFixture {
  static let locale = Locale(identifier: "ko_KR")

  static func model(
    photoStore: PhotoStoreClientFake?,
    clock: TestClock = TestClock(now: .seoul(2026, 10, 21, hour: 9), calendar: .seoul),
    locale: Locale = SearchFixture.locale,
    waitGates: CallGates? = nil,
    buildGates: CallGates? = nil,
    matchGates: CallGates? = nil
  ) -> (model: SearchModel, probe: SearchProbe) {
    let probe = SearchProbe()
    let waitCounter = CallCounter()
    let buildCounter = CallCounter()
    let matchCounter = CallCounter()
    let model = SearchModel(
      photoStore: photoStore,
      calendar: { clock.calendar },
      locale: { locale },
      wait: { duration in
        probe.waited(duration)
        if let waitGates {
          await waitGates.pass(waitCounter.next())
        }
        try Task.checkCancellation()
      },
      building: { load, previous in
        probe.built()
        if let buildGates {
          await buildGates.pass(buildCounter.next())
        }
        return await SearchComputing.source(from: load, reusing: previous)
      },
      matching: { source, query, current in
        probe.matched(query)
        if let matchGates {
          await matchGates.pass(matchCounter.next())
        }
        return await SearchComputing.results(in: source, query: query, comparingTo: current)
      }
    )
    return (model, probe)
  }

  /// 가게 이름이 든 문서 사진 하나.
  static let starbucks = IndexedImage.searchable(
    id: "starbucks",
    ["스타벅스 아메리카노", "4,500원"],
    at: .seoul(2026, 10, 14, hour: 12)
  )
  static let coupangCapture = IndexedImage.searchable(
    id: "coupang",
    ["로켓배송 도착"],
    at: .seoul(2026, 10, 13, hour: 12),
    categories: [.shopping],
    captureGroups: CaptureGroups(mall: ShoppingMall(id: "coupang"))
  )
}

extension IndexedImage {
  /// 글자를 읽은 이미지. 기본은 문서다.
  static func searchable(
    id: String,
    _ lines: [String],
    at date: Date? = nil,
    categories: Set<ImageCategory> = [.document],
    captureGroups: CaptureGroups? = nil
  ) -> IndexedImage {
    IndexedImage(
      asset: .stub(id: id, creationDate: date),
      labels: [],
      textRecognition: .recognized(lines.map(RecognizedTextLine.stub)),
      categories: categories,
      captureGroups: captureGroups
    )
  }

  /// 글자를 아직 읽지 않은 이미지(OCR 대기).
  static func unreadText(id: String, at date: Date? = nil) -> IndexedImage {
    IndexedImage(
      asset: .stub(id: id, creationDate: date),
      labels: [],
      textRecognition: .pending,
      categories: [.document]
    )
  }
}

extension SearchModel {
  /// 지금 결과의 사진 식별자, 최신순. 결과가 없으면 nil.
  var resultImageIDs: [ImageAsset.ID]? {
    self.results?.images.map(\.id)
  }
}
