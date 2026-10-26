import Core
import CoreGraphics
import Foundation
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting

/// Example 의 분류 결과와 그 이미지 읽기 결과. 저장소와 보관함 대역이 같은 식별자를 쓴다.
enum PreviewPhotos {
  /// 카테고리별 이미지 수. "인물"은 긴 격자를 확인하려고 1,200장이다. 기프티콘·영수증은 데모 줄 수(`PreviewGifticons.demos`·
  /// `PreviewReceipts.demos`)이고, 쇼핑·대화·지도는 묶기 데모 수(`PreviewCaptureGroups`)다.
  static let counts: [(ImageCategory, Int)] = [
    (.gifticon, PreviewGifticons.demos.count), (.receipt, PreviewReceipts.demos.count),
  ] + PreviewCaptureGroups.counts + [
    (.document, 4), (.food, 21), (.people, 1200), (.landscape, 6), (.other, 3),
  ]
  /// 각 카테고리 마지막 이만큼은 생성일이 없다("날짜 없음" 섹션).
  static let undatedCount = 5
  /// 데모 버튼으로 더할 수 있는 새 사진 수. 읽기 결과를 미리 만들어 둔다.
  static let newPhotoCapacity = 50

  static func id(_ category: ImageCategory, _ index: Int) -> ImageAsset.ID {
    "\(category.rawValue)-\(index)"
  }

  static func newPhotoID(_ index: Int) -> ImageAsset.ID {
    "people-new-\(index)"
  }

  /// 최근 24개월에 고르게 퍼진 생성일. 마지막 `undatedCount` 장은 nil 이다.
  static func creationDate(index: Int, count: Int) -> Date? {
    let datedCount = max(count - self.undatedCount, 1)
    guard index < datedCount else { return nil }
    let span: TimeInterval = 730 * 86400
    return Date().addingTimeInterval(-span * Double(index) / Double(datedCount))
  }

  /// 칸마다 색이 다른 작은 이미지. 50장마다 iCloud 에만 있음·실패·보관함에 없음(결과 없음)·작은 대체 버전이 하나씩 섞인다.
  /// 기프티콘은 바코드가 그려진 이미지(`PreviewGifticons.loadImageResults`)다. 데모 버튼으로 더한 새 사진은 모두 읽힌다.
  static let loadImageResults: [ImageAsset.ID: Result<AnalysisImage, ImageLoadError>] = {
    var results: [ImageAsset.ID: Result<AnalysisImage, ImageLoadError>] = [:]
    let ids = PreviewPhotos.counts.flatMap { category, count in (0 ..< count).map { PreviewPhotos.id(category, $0) } }
    for (index, id) in ids.enumerated() {
      switch index % 50 {
      case 7: results[id] = .failure(.notAvailableLocally)
      case 13: results[id] = .failure(.failed)
      case 21: break
      default: results[id] = .success(PreviewPhotos.image(index: index, isLocalFallback: index % 50 == 3))
      }
    }
    results.merge(PreviewGifticons.loadImageResults) { _, gifticon in gifticon }
    for (index, id) in PreviewTrips.imageIDs.enumerated() {
      results[id] = .success(PreviewPhotos.image(index: index, isLocalFallback: false))
    }
    for index in 0 ..< PreviewPhotos.newPhotoCapacity {
      results[PreviewPhotos.newPhotoID(index)] = .success(PreviewPhotos.image(index: index, isLocalFallback: false))
    }
    for (index, id) in PreviewSearch.imageIDs.enumerated() {
      results[id] = .success(PreviewPhotos.image(index: index, isLocalFallback: false))
    }
    for (index, id) in PreviewCleanup.imageIDs.enumerated() {
      results[id] = .success(PreviewPhotos.image(index: index, isLocalFallback: false))
    }
    return results
  }()

  private static func image(index: Int, isLocalFallback: Bool) -> AnalysisImage {
    AnalysisImage(cgImage: .colored(index: index), orientation: .up, isLocalFallback: isLocalFallback)
  }
}

extension CGImage {
  /// 한 색으로 채운 40×30 이미지. 이웃한 `index` 끼리 색이 다르다.
  static func colored(index: Int) -> CGImage {
    let width = 40
    let height = 30
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
    else { return .stub(width: width, height: height) }
    context.setFillColor(
      red: CGFloat(index * 37 % 200 + 40) / 255,
      green: CGFloat(index * 67 % 200 + 40) / 255,
      blue: CGFloat(index * 101 % 200 + 40) / 255,
      alpha: 1
    )
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage() ?? .stub(width: width, height: height)
  }
}

extension PhotoStoreClientFake {
  /// 정보형·사진형 카테고리와 여행이 섞인 분류 결과(`PreviewPhotos`). Preview 마다 새로 만들어 서로 상태를 나누지 않는다.
  /// 기프티콘은 `PreviewGifticons.demos`, 영수증은 `PreviewReceipts.demos`, 쇼핑·대화·지도는 `PreviewCaptureGroups` 의 상태들이고,
  /// 문서 첫 장은 주소·송장·계좌번호가 있는 캡처다.
  /// 여행은 `PreviewTrips` 의 세 여행과 그 사진·캡처, 제주의 장소 캐시다.
  /// - Parameters:
  ///   - hasUpcomingExpiry: 거짓이면 기프티콘의 만료일을 찾지 못한 것으로 둔다(만료 알림을 예약할 수 없다).
  ///   - includesGifticons: 거짓이면 기프티콘이 없다(빈 기프티콘 목록은 Preview 에서 본다).
  ///   - assetsErrors: 카테고리 화면 읽기(`assets(in:)`)의 호출 번호별 실패.
  ///   - gifticonsErrors: 기프티콘 목록 읽기(`gifticons()`)의 호출 번호별 실패.
  ///   - includesTrips: 거짓이면 여행이 없다(보관함에 여행 줄이 없다. 빈 여행 목록은 Preview 에서 본다).
  ///   - tripsErrors: 여행 읽기(`trips()`)의 호출 번호별 실패.
  ///   - receiptsErrors: 영수증 목록 읽기(`receipts()`)의 호출 번호별 실패.
  ///   - captureGroupItemsErrors: 쇼핑·대화·지도 카테고리 읽기(`captureGroupItems(in:)`)의 호출 번호별 실패.
  ///   - searchEntriesErrors·onSearchEntries: 검색 목록 읽기(`searchEntries()`)의 호출 번호별 실패와 읽은 뒤 기다리는 훅.
  ///   - captureInboxErrors: 캡처 인박스 읽기(`captureInboxScreenshots(createdSince:)`)의 호출 번호별 실패.
  ///   - extraImages: 분류 결과에 더하는 이미지. 정리 도우미 데모의 스크린샷·비슷한 사진(`PreviewCleanup`)을 더할 때 쓴다.
  ///   - allReceiptsChecking: 참이면 영수증이 모두 확인 중이다(데모 짝수 번은 OCR 대기, 홀수 번과 여행 영수증은 추출 대기).
  static func previewClassified(
    hasUpcomingExpiry: Bool = true,
    includesGifticons: Bool = true,
    assetsErrors: [Int: PhotoStoreError] = [:],
    gifticonsErrors: [Int: PhotoStoreError] = [:],
    includesTrips: Bool = true,
    tripsErrors: [Int: PhotoStoreError] = [:],
    receiptsErrors: [Int: PhotoStoreError] = [:],
    captureGroupItemsErrors: [Int: PhotoStoreError] = [:],
    allReceiptsChecking: Bool = false,
    searchEntriesErrors: [Int: PhotoStoreError] = [:],
    onSearchEntries: @escaping @Sendable (Int) async -> Void = { _ in },
    captureInboxErrors: [Int: PhotoStoreError] = [:],
    extraImages: [IndexedImage] = []
  ) -> PhotoStoreClientFake {
    let now = Date()
    let today = LocalDate(now, calendar: .current)
    let others = PreviewPhotos.otherImages()
    let gifticons = PreviewGifticons.images(today: today, now: now).map { image in
      guard !hasUpcomingExpiry, let gifticon = image.gifticon else { return image }
      return IndexedImage(
        asset: image.asset,
        labels: [],
        textRecognition: image.textRecognition,
        categories: image.categories,
        gifticon: GifticonInfo(expiryDate: nil, redemptionPlace: gifticon.redemptionPlace),
        gifticonModelFill: image.gifticonModelFill
      )
    }
    return PhotoStoreClientFake(
      images: others + (includesGifticons ? gifticons : []) + PreviewReceipts.images(allChecking: allReceiptsChecking)
        + PreviewCaptureGroups
        .images() + PreviewSearch
        .images() + (includesTrips ? PreviewTrips.images(receiptsChecking: allReceiptsChecking) : []) + extraImages,
      trips: includesTrips ? PreviewTrips.trips : [],
      assetsErrors: assetsErrors,
      usedIDs: PreviewGifticons.usedIDs,
      gifticonsErrors: gifticonsErrors,
      places: includesTrips ? PreviewTrips.places : [:],
      placesLocaleIdentifier: PreviewTrips.placesLocaleIdentifier,
      tripsErrors: tripsErrors,
      receiptsErrors: receiptsErrors,
      captureGroupItemsErrors: captureGroupItemsErrors,
      searchEntriesErrors: searchEntriesErrors,
      onSearchEntries: onSearchEntries,
      captureInboxErrors: captureInboxErrors
    )
  }
}

extension PreviewPhotos {
  /// 기프티콘·영수증·캡처 묶음 카테고리를 뺀 나머지 카테고리의 사진. 문서 첫 장은 주소·송장·계좌번호가 있는 캡처다.
  static func otherImages() -> [IndexedImage] {
    self.counts.filter {
      $0.0 != .gifticon && $0.0 != .receipt && !PreviewCaptureGroups.categories.contains($0.0)
    }.flatMap { category, count in
      (0 ..< count).map { index in
        let isCapture = category == .document && index == 0
        return IndexedImage(
          asset: .stub(
            id: self.id(category, index),
            creationDate: self.creationDate(index: index, count: count)
          ),
          labels: [],
          textRecognition: isCapture
            ? .recognized(PreviewGifticons.captureLines.map {
              RecognizedTextLine(text: $0, confidence: 1, boundingBox: .zero)
            })
            : .notNeeded,
          categories: [category]
        )
      }
    }
  }
}
