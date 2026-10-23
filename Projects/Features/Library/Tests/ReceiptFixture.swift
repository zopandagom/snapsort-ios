import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
@testable import LibraryFeature

/// 영수증 목록 테스트의 공통 준비. 기기 달력은 Asia/Seoul 로 시작한다(`TestClock` 으로 바꾼다).
/// 가게·금액은 지어낸 값이다.
@MainActor
enum ReceiptFixture {
  static func listModel(
    photoStore: PhotoStoreClientFake?,
    clock: TestClock = TestClock(now: GifticonFixture.now, calendar: .seoul)
  ) -> ReceiptListModel {
    ReceiptListModel(photoStore: photoStore, calendar: { clock.calendar })
  }

  static func info(_ storeName: String?, won: Int?, isCancelled: Bool = false) -> ReceiptInfo {
    ReceiptInfo(
      storeName: storeName,
      amount: won.flatMap { ReceiptAmount(minorUnits: $0, currency: .krw) },
      isCancelled: isCancelled
    )
  }
}

extension IndexedImage {
  /// 글자를 읽은 영수증. `info` 가 nil 이면 추출 대기(목록의 "확인 중")다.
  static func receipt(id: String, creationDate: Date? = nil, info: ReceiptInfo?) -> IndexedImage {
    IndexedImage(
      asset: .stub(id: id, creationDate: creationDate),
      labels: [],
      textRecognition: .recognized([.stub("합계 9,000")]),
      categories: [.receipt],
      receipt: info
    )
  }
}

extension ReceiptListContent {
  /// 읽은 항목의 식별자. 읽기 전이나 실패면 nil.
  var ids: [ImageAsset.ID]? {
    self.items?.map(\.id)
  }

  var items: [ReceiptListItem]? {
    guard case let .loaded(items) = self else { return nil }
    return items
  }
}
