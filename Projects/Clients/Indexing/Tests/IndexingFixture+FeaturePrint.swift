import Core
import Foundation
import ImageAnalysisTesting
import PhotoLibraryTesting
import PhotoStoreInterface

// 특징 벡터 테스트의 준비.

/// `Fixture` 의 특징 벡터 설정.
struct FeaturePrintOptions {
  /// 분석 Fake 가 벡터를 쓸 수 있는지.
  var isAvailable = false
  /// 벡터 요청에 실패하는 이미지(`Fixture.featurePrintFailures` 로 테스트 도중 바꿀 수 있다).
  var failures: Set<ImageAsset.ID> = []
  /// 썸네일이 대체 버전(iCloud 전용 사진의 작은 버전)으로 읽히는 이미지.
  var localFallbackIDs: Set<ImageAsset.ID> = []
  /// 벡터를 요청할 때마다 결과 전에 부른다. 인자는 식별자와 분석 Fake. 쓸 수 없게 바꾸면(`makeFeaturePrintUnavailable`) 그 요청은 실패한다.
  var onFeaturePrint: @Sendable (ImageAsset.ID, ImageAnalysisClientFake?) async -> Void = { _, _ in }
  /// 저장소의 벡터 소급 호출(대기 조회·벡터 저장)만의 실패.
  var storeError: PhotoStoreError?
  /// 저장소가 벡터를 이 횟수만큼 저장한 뒤부터 실패한다.
  var saveLimit: Int?

  static let available = FeaturePrintOptions(isAvailable: true)
}

/// 분석 Fake 가 그 폭의 썸네일에 주는 벡터. 이미지마다 다르다.
func fixtureFeaturePrint(width: Int) -> ImageFeaturePrint {
  var values = [Float](repeating: 0, count: ImageFeaturePrint.elementCount)
  values[0] = Float(width)
  return ImageFeaturePrint(values: values)!
}

/// 벡터 대상 카메라 사진. `day` 가 클수록 최신이다.
func cameraPhoto(_ id: String, day: Int) -> ImageAsset {
  .stub(id: id, creationDate: date(month: 5, day: day))
}

/// 1단계를 마친 OCR 대상 아닌 사진 저장 결과. `featurePrint` 가 nil 이면 벡터 대기다.
func classifiedPhoto(_ asset: ImageAsset, featurePrint: ImageFeaturePrint? = nil) -> IndexedImage {
  IndexedImage(
    asset: asset,
    labels: photoLabels,
    textRecognition: .notNeeded,
    categories: RuleClassifier.classify(asset: asset, labels: photoLabels, textLines: []),
    featurePrint: featurePrint
  )
}

extension Fixture {
  /// 저장소의 이미지별 벡터 유무.
  var storedFeaturePrints: [ImageAsset.ID: ImageFeaturePrint] {
    self.store.images.reduce(into: [:]) { result, image in
      result[image.id] = image.featurePrint
    }
  }

  /// 분석 Fake 가 받은 벡터 요청 수.
  var featurePrintRequestCount: Int {
    self.analysis.requests.count { $0 == .featurePrint }
  }

  /// 썸네일로 읽은 식별자를 순서대로.
  var thumbnailLoadIDs: [ImageAsset.ID] {
    self.photoLibrary.loadImageRequests.filter { $0.size == .thumbnail }.map(\.id)
  }
}
