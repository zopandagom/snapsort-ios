import Core
import CoreGraphics
import Foundation
import ImageAnalysisInterface
import ImageAnalysisTesting
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting

/// 스토어 스크린샷 시나리오(`ExampleScenario.storeScreenshots`)의 데이터. 기존 데모(`PreviewPhotos` 등, 실제 브랜드 이름이 든 것)와
/// 섞지 않으려고 식별자(`store-…`)·값을 모두 따로 둔다. 교환처·가게·상품·번호·문장은 모두 지어낸 값이고, 여행 좌표는 공공 명소 부근의
/// 데모 값일 뿐 실제 사람의 위치가 아니다. 주소·전화·송장·계좌 형식의 글자는 쓰지 않는다(docs/CONVENTIONS.md §4 스토어 스크린샷 데이터).
/// 실행일과 무관하게 같은 화면이 나오도록 "지금"은 2026-11-03 09:41(서울)로 고정하고, 달력은 그레고리력·서울 시간대·한국어다.
enum StoreScreenshotData {
  static let timeZone = TimeZone(identifier: "Asia/Seoul") ?? TimeZone(secondsFromGMT: 9 * 3600) ?? .current
  static let locale = Locale(identifier: "ko_KR")
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = StoreScreenshotData.timeZone
    calendar.locale = StoreScreenshotData.locale
    return calendar
  }()

  static let now = StoreScreenshotData.date(2026, 11, 3, hour: 9, minute: 41)
  static let today = LocalDate(StoreScreenshotData.now, calendar: StoreScreenshotData.calendar)

  /// 곧 만료 배지(D-3 이내 미사용)는 숨 쉬듯 움직여 캡처마다 크기가 달라진다. 시뮬레이터의 동작 줄이기가 앱에 반영되지 않으면
  /// 이 값을 참으로 바꿔 가장 급한 두 장을 D-4·D-6 으로 둔다(움직이는 배지 없음). 거짓이면 D-1·D-3 이다.
  static let avoidsPulsingBadges = false

  static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int = 0) -> Date {
    self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
      ?? Date(timeIntervalSince1970: 1_793_673_660)
  }

  /// 고정 "지금"에서 `days` 일과 `minutes` 분 전.
  static func ago(days: Double, minutes: Double = 0) -> Date {
    self.now.addingTimeInterval(-days * 86400 - minutes * 60)
  }

  static func id(_ kind: String, _ index: Int) -> ImageAsset.ID {
    "store-\(kind)-\(index)"
  }

  // MARK: - 기프티콘

  struct GifticonDemo {
    let place: String
    let product: String
    let shape: StoreScreenshotArtwork.ProductShape
    let color: StoreScreenshotArtwork.RGB
    let expiryInDays: Int
    var isUsed = false
  }

  /// 바코드 대역이 이미지 너비 - 이 값으로 장을 찾는다.
  static let gifticonBaseWidth = 900

  /// 줄 순서가 식별자 번호다. 0번이 상세(3번 화면)에 보인다. 7번은 사용함, 8번은 만료됨(정리 후보).
  static let gifticons: [GifticonDemo] = [
    GifticonDemo(
      place: "달무리커피",
      product: "아메리카노",
      shape: .cup,
      color: StoreScreenshotArtwork.RGB(0.45, 0.30, 0.22),
      expiryInDays: StoreScreenshotData.avoidsPulsingBadges ? 4 : 1
    ),
    GifticonDemo(
      place: "솜구름제과",
      product: "생크림 케이크",
      shape: .cake,
      color: StoreScreenshotArtwork.RGB(0.82, 0.50, 0.30),
      expiryInDays: StoreScreenshotData.avoidsPulsingBadges ? 6 : 3
    ),
    GifticonDemo(
      place: "소풍분식",
      product: "떡볶이 세트",
      shape: .bowl,
      color: StoreScreenshotArtwork.RGB(0.88, 0.36, 0.30),
      expiryInDays: 6
    ),
    GifticonDemo(
      place: "몽실아이스",
      product: "파인트",
      shape: .iceCream,
      color: StoreScreenshotArtwork.RGB(0.58, 0.48, 0.84),
      expiryInDays: 12
    ),
    GifticonDemo(
      place: "초록편의점",
      product: "모바일 상품권 5천원",
      shape: .card,
      color: StoreScreenshotArtwork.RGB(0.28, 0.60, 0.42),
      expiryInDays: 27
    ),
    GifticonDemo(
      place: "별빛영화관",
      product: "관람권",
      shape: .ticket,
      color: StoreScreenshotArtwork.RGB(0.25, 0.28, 0.50),
      expiryInDays: 58
    ),
    GifticonDemo(
      place: "하늘책방",
      product: "도서 교환권",
      shape: .book,
      color: StoreScreenshotArtwork.RGB(0.30, 0.55, 0.80),
      expiryInDays: 90
    ),
    GifticonDemo(
      place: "바람버거",
      product: "세트 메뉴",
      shape: .burger,
      color: StoreScreenshotArtwork.RGB(0.85, 0.52, 0.20),
      expiryInDays: 5,
      isUsed: true
    ),
    GifticonDemo(
      place: "노을주스",
      product: "생과일 주스",
      shape: .juice,
      color: StoreScreenshotArtwork.RGB(0.94, 0.48, 0.40),
      expiryInDays: -9
    ),
  ]

  static func gifticonID(_ index: Int) -> ImageAsset.ID {
    self.id("gifticon", index)
  }

  static func barcodePayload(_ index: Int) -> String {
    String(format: "0941-2026-1103-%02d", index + 1)
  }

  static func gifticonExpiry(_ index: Int) -> LocalDate {
    self.today.addingDays(self.gifticons[index].expiryInDays)
  }

  static var usedIDs: Set<ImageAsset.ID> {
    Set(self.gifticons.indices.filter { self.gifticons[$0].isUsed }.map(self.gifticonID))
  }

  static func gifticonImages() -> [IndexedImage] {
    self.gifticons.enumerated().map { index, demo in
      IndexedImage(
        asset: .stub(
          id: self.gifticonID(index),
          creationDate: self.ago(days: Double(index + 1), minutes: 37),
          pixelWidth: 1320,
          pixelHeight: 2868,
          isScreenshot: true
        ),
        labels: [],
        textRecognition: .recognized([]),
        categories: [.gifticon],
        gifticon: GifticonInfo(expiryDate: self.gifticonExpiry(index), redemptionPlace: demo.place),
        gifticonModelFill: .done
      )
    }
  }

  /// 목록에서 연 것처럼 상세에 넘길 항목.
  static func gifticonItem(_ index: Int) -> GifticonListItem {
    let image = self.gifticonImages()[index]
    return GifticonListItem(
      asset: image.asset,
      status: image.gifticon.map { .extracted($0) } ?? .checking,
      isUsed: self.gifticons[index].isUsed
    )
  }

  /// 기프티콘 목록의 미사용(만료 전) 섹션 순서(만료일 오름차순). 상세는 이 장들을 넘긴다.
  static var unusedGifticonIndices: [Int] {
    self.gifticons.indices
      .filter { !self.gifticons[$0].isUsed && self.gifticons[$0].expiryInDays >= 0 }
      .sorted { self.gifticons[$0].expiryInDays < self.gifticons[$1].expiryInDays }
  }

  static func gifticonArtwork(_ index: Int) -> CGImage {
    let demo = self.gifticons[index]
    let expiry = self.gifticonExpiry(index)
    return StoreScreenshotArtwork.gifticon(
      StoreScreenshotArtwork.Gifticon(
        place: demo.place,
        product: demo.product,
        shape: demo.shape,
        color: demo.color,
        barcodeText: self.barcodePayload(index),
        expiryText: String(format: "유효기간 %04d.%02d.%02d", expiry.year, expiry.month, expiry.day)
      ),
      width: self.gifticonBaseWidth + index
    )
  }

  /// 이미지 너비로 기프티콘 장을 찾아 지어낸 Code128 값을 준다. 기프티콘이 아닌 이미지는 바코드가 없다.
  static func detectBarcodes(_ image: AnalysisImage) -> Result<[DetectedBarcode], ImageAnalysisError> {
    let index = image.cgImage.width - self.gifticonBaseWidth
    guard image.cgImage.height == StoreScreenshotArtwork.gifticonHeight, self.gifticons.indices.contains(index) else {
      return .success([])
    }
    return .success([DetectedBarcode(
      payload: self.barcodePayload(index),
      symbology: .code128,
      boundingBox: StoreScreenshotArtwork.barcodeBox
    )])
  }
}

extension ImageAnalysisClientFake {
  /// 스토어 시나리오의 바코드 결과를 준다.
  static func storeScreenshots() -> ImageAnalysisClientFake {
    ImageAnalysisClientFake(
      classify: { _ in .success([]) },
      recognizeText: { _ in .success([]) },
      detectBarcodes: { StoreScreenshotData.detectBarcodes($0) }
    )
  }
}
