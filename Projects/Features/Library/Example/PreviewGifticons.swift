import Core
import CoreGraphics
import Foundation
import ImageAnalysisInterface
import ImageAnalysisTesting
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface

/// Example 의 기프티콘·캡처 데모. 앱을 켠 날을 오늘로 보고 만료일을 정한다.
/// 줄마다 확인할 상태가 하나씩 있고, 바코드 인식 결과는 이미지 너비로 고른다(`detectBarcodes`).
enum PreviewGifticons {
  struct Demo {
    let creationDaysAgo: Int
    /// 오늘부터 며칠 뒤 만료인지. nil 이면 만료일을 찾지 못했다.
    let expiryInDays: Int?
    let place: String?
    var status: Status = .extracted
    var modelFilledFields: Set<GifticonInfo.Field> = []
    var modelFill: GifticonModelFill = .done
    var isUsed = false
    var barcode: Barcode = .code128
  }

  enum Status {
    case extracted
    /// 글자를 아직 읽지 않았다(OCR 대기).
    case waitingForText
    /// 글자를 읽었고 추출 대기다.
    case waitingForExtraction
  }

  enum Barcode {
    /// Code128 "1234567890123" (다시 그림).
    case code128
    /// QR "GIFT-0001-2026" (다시 그림).
    case qrCode
    /// EAN-13 (원본 영역 자르기).
    case ean13
    case none
    case failure
  }

  /// 줄 순서가 식별자 번호다(`PreviewPhotos.id(.gifticon, index)`).
  static let demos: [Demo] = [
    Demo(creationDaysAgo: 1, expiryInDays: 0, place: "스타벅스"),
    Demo(creationDaysAgo: 2, expiryInDays: 1, place: "GS25", barcode: .qrCode),
    Demo(creationDaysAgo: 3, expiryInDays: 7, place: "배스킨라빈스", barcode: .ean13),
    // 작은 대체 버전이라 바코드를 찾지 못했을 수 있다는 안내.
    Demo(
      creationDaysAgo: 4,
      expiryInDays: PreviewGifticons.daysUntilNextYear(month: 1, day: 2),
      place: "교보문고",
      barcode: .none
    ),
    Demo(creationDaysAgo: 5, expiryInDays: -1, place: "CU", barcode: .failure),
    Demo(creationDaysAgo: 40, expiryInDays: -35, place: "메가커피"),
    Demo(creationDaysAgo: 6, expiryInDays: nil, place: "올리브영"),
    // iCloud 에만 있어 상세 이미지를 볼 수 없다.
    Demo(creationDaysAgo: 7, expiryInDays: nil, place: nil, status: .waitingForText),
    Demo(creationDaysAgo: 8, expiryInDays: nil, place: nil, status: .waitingForExtraction),
    Demo(creationDaysAgo: 9, expiryInDays: 20, place: "투썸플레이스", modelFilledFields: [.expiryDate]),
    Demo(creationDaysAgo: 10, expiryInDays: 30, place: "롯데시네마", modelFilledFields: [.redemptionPlace]),
    // 옛 보강 버전·출처 모름: 값이 있는 필드가 모두 "추정".
    Demo(creationDaysAgo: 11, expiryInDays: 14, place: "이디야", modelFill: .stale),
    Demo(creationDaysAgo: 12, expiryInDays: 45, place: "파리바게뜨", modelFill: .sourcesUnknown),
    Demo(creationDaysAgo: 13, expiryInDays: 3, place: "버거킹", isUsed: true),
    Demo(creationDaysAgo: 50, expiryInDays: -10, place: "맘스터치", isUsed: true),
  ]

  /// 주소·송장·계좌번호가 있는 캡처(`PreviewPhotos.id(.document, 0)`)의 OCR 줄. 지어낸 값이다.
  static let captureLines = ["서울특별시 중구 세종대로 110", "CJ대한통운 1234-5678-9012", "신한은행 110-123-456789"]

  static let imageBaseWidth = 300
  /// 바코드가 그려진 자리(바르게 돌린 기준 정규화, 원점 왼쪽 위).
  static let barcodeBox = CGRect(x: 0.15, y: 0.62, width: 0.7, height: 0.16)

  static func images(today: LocalDate, now: Date) -> [IndexedImage] {
    self.demos.enumerated().map { index, demo in
      let asset = ImageAsset.stub(
        id: PreviewPhotos.id(.gifticon, index),
        creationDate: now.addingTimeInterval(-Double(demo.creationDaysAgo) * 86400),
        isScreenshot: true
      )
      switch demo.status {
      case .waitingForText:
        return IndexedImage(asset: asset, labels: [], textRecognition: .pending, categories: [.gifticon])
      case .waitingForExtraction:
        return IndexedImage(asset: asset, labels: [], textRecognition: .recognized([]), categories: [.gifticon])
      case .extracted:
        return IndexedImage(
          asset: asset,
          labels: [],
          textRecognition: .recognized([]),
          categories: [.gifticon],
          gifticon: GifticonInfo(
            expiryDate: demo.expiryInDays.map { today.addingDays($0) },
            redemptionPlace: demo.place,
            modelFilledFields: demo.modelFilledFields
          ),
          gifticonModelFill: demo.modelFill
        )
      }
    }
  }

  static var usedIDs: Set<ImageAsset.ID> {
    Set(self.demos.enumerated().filter(\.element.isUsed).map { PreviewPhotos.id(.gifticon, $0.offset) })
  }

  /// 기프티콘 이미지 읽기 결과. 7번(OCR 대기)은 iCloud 에만 있고, 3번은 작은 대체 버전이다.
  static var loadImageResults: [ImageAsset.ID: Result<AnalysisImage, ImageLoadError>] {
    Dictionary(uniqueKeysWithValues: self.demos.indices.map { index in
      let result: Result<AnalysisImage, ImageLoadError> = index == 7
        ? .failure(.notAvailableLocally)
        : .success(AnalysisImage(cgImage: .gifticon(index: index), orientation: .up, isLocalFallback: index == 3))
      return (PreviewPhotos.id(.gifticon, index), result)
    })
  }

  /// 이미지 너비로 데모 줄을 찾아 정해 둔 바코드 결과를 준다. 기프티콘이 아닌 이미지는 바코드가 없다.
  static func detectBarcodes(_ image: AnalysisImage) -> Result<[DetectedBarcode], ImageAnalysisError> {
    let index = image.cgImage.width - self.imageBaseWidth
    guard self.demos.indices.contains(index) else { return .success([]) }
    switch self.demos[index].barcode {
    case .code128:
      return .success([DetectedBarcode(payload: "1234567890123", symbology: .code128, boundingBox: self.barcodeBox)])
    case .qrCode:
      return .success([DetectedBarcode(payload: "GIFT-0001-2026", symbology: .qrCode, boundingBox: self.barcodeBox)])
    case .ean13:
      return .success([DetectedBarcode(payload: "8801234567893", symbology: .ean13, boundingBox: self.barcodeBox)])
    case .none:
      return .success([])
    case .failure:
      return .failure(.failed)
    }
  }

  /// 오늘부터 내년 `month`월 `day`일까지의 일수(연말을 넘는 만료일).
  private static func daysUntilNextYear(month: Int, day: Int) -> Int {
    let today = LocalDate(Date(), calendar: .current)
    guard let target = LocalDate(year: today.year + 1, month: month, day: day) else { return 60 }
    return today.days(until: target)
  }
}

extension ImageAnalysisClientFake {
  /// 기프티콘 데모의 바코드 결과를 준다.
  static func previewGifticons() -> ImageAnalysisClientFake {
    ImageAnalysisClientFake(
      classify: { _ in .success([]) },
      recognizeText: { _ in .success([]) },
      detectBarcodes: { PreviewGifticons.detectBarcodes($0) }
    )
  }
}

extension CGImage {
  /// 기프티콘처럼 보이는 세로 이미지: 색 머리띠와 아래쪽 바코드 줄무늬(`PreviewGifticons.barcodeBox`).
  /// 너비가 데모 번호를 담는다(`imageBaseWidth + index`).
  static func gifticon(index: Int) -> CGImage {
    let width = PreviewGifticons.imageBaseWidth + index
    let height = 500
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return .colored(index: index) }
    context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // CGContext 원점은 왼쪽 아래다. 머리띠는 위쪽 30%.
    context.setFillColor(
      red: CGFloat(index * 37 % 200 + 40) / 255,
      green: CGFloat(index * 67 % 200 + 40) / 255,
      blue: CGFloat(index * 101 % 200 + 40) / 255,
      alpha: 1
    )
    context.fill(CGRect(x: 0, y: Double(height) * 0.7, width: Double(width), height: Double(height) * 0.3))
    let box = PreviewGifticons.barcodeBox
    let barTop = Double(height) * (1 - box.minY)
    let barHeight = Double(height) * box.height
    context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
    var x = Double(width) * box.minX
    var stripe = 0
    while x < Double(width) * box.maxX {
      let stripeWidth = Double(stripe % 3 + 1)
      if stripe.isMultiple(of: 2) {
        context.fill(CGRect(x: x, y: barTop - barHeight, width: stripeWidth, height: barHeight))
      }
      x += stripeWidth
      stripe += 1
    }
    return context.makeImage() ?? .colored(index: index)
  }
}
