import Core
import Foundation
import ImageAnalysisInterface
import ImageAnalysisTesting
import PhotoLibraryInterface
import PhotoLibraryTesting
@testable import IndexingImpl

// IndexingClientImplTests 의 테스트 준비: 보관함·분류·OCR Fake 의 결과를 만든다.
extension Fixture {
  /// 보관함 Fake. 이미지마다 `widths` 폭의 썸네일을 돌려주고, `loadErrors` 가 있으면 그 실패를 던진다.
  static func photoLibrary(
    _ library: [ImageAsset],
    widths: [ImageAsset.ID: Int],
    loadErrors: [ImageAsset.ID: ImageLoadError],
    accessState: PhotoAccessState
  ) -> PhotoLibraryClientFake {
    PhotoLibraryClientFake(
      currentState: accessState,
      imageAssets: library,
      loadImageResults: widths.reduce(into: [:]) { results, entry in
        results[entry.key] = loadErrors[entry.key].map { .failure($0) } ?? .success(.stub(
          width: entry.value,
          height: 1
        ))
      }
    )
  }

  /// 분류 Fake 의 결과. 폭으로 이미지를 찾아 `onClassify` 를 부른 뒤 `failures`·`labels` 로 고른다.
  static func classifier(
    idsByWidth: [Int: ImageAsset.ID],
    labels: [ImageAsset.ID: [ImageLabel]],
    failures: FailingIDs,
    onClassify: @escaping @Sendable (ImageAsset.ID) -> Void
  ) -> @Sendable (AnalysisImage) async -> Result<[ImageLabel], ImageAnalysisError> {
    { image in
      let id = idsByWidth[image.cgImage.width] ?? ""
      onClassify(id)
      return failures.contains(id) ? .failure(.failed) : .success(labels[id] ?? defaultLabels)
    }
  }

  /// OCR Fake 의 결과. 폭으로 이미지를 찾아 `onRecognize` 를 부른 뒤 `failures`·`text` 로 고른다.
  static func recognizer(
    idsByWidth: [Int: ImageAsset.ID],
    text: [ImageAsset.ID: [String]],
    failures: FailingIDs,
    onRecognize: @escaping @Sendable (ImageAsset.ID) async -> Void
  ) -> @Sendable (AnalysisImage) async -> Result<[RecognizedTextLine], ImageAnalysisError> {
    { image in
      let id = idsByWidth[image.cgImage.width] ?? ""
      await onRecognize(id)
      if failures.contains(id) {
        return .failure(.failed)
      }
      return .success(ocrLines(text[id] ?? []))
    }
  }

  /// 분석 Fake. 특징 벡터는 `featurePrint` 설정대로 쓸 수 있음을 정하고 `featurePrinter` 로 결과를 만든다.
  static func analysis(
    classify: @escaping @Sendable (AnalysisImage) async -> Result<[ImageLabel], ImageAnalysisError>,
    recognizeText: @escaping @Sendable (AnalysisImage) async -> Result<[RecognizedTextLine], ImageAnalysisError>,
    detectBarcodes: @escaping @Sendable (AnalysisImage) async -> Result<[DetectedBarcode], ImageAnalysisError>,
    featurePrint: (options: FeaturePrintOptions, failures: FailingIDs),
    idsByWidth: [Int: ImageAsset.ID]
  ) -> ImageAnalysisClientFake {
    let later = Later<ImageAnalysisClientFake>()
    let analysis = ImageAnalysisClientFake(
      classify: classify,
      recognizeText: recognizeText,
      detectBarcodes: detectBarcodes,
      isFeaturePrintAvailable: featurePrint.options.isAvailable,
      isFeaturePrintAvailableInBackground: featurePrint.options.isAvailableInBackground,
      featurePrint: Self.featurePrinter(
        idsByWidth: idsByWidth,
        failures: featurePrint.failures,
        analysis: later,
        onFeaturePrint: featurePrint.options.onFeaturePrint
      )
    )
    later.set(analysis)
    return analysis
  }

  /// 특징 벡터 Fake 의 결과. 폭으로 이미지를 찾아 `onFeaturePrint` 를 부른 뒤, `failures` 에 있거나 훅이 쓸 수 없게 바꿨으면 실패,
  /// 아니면 첫 원소가 폭인 벡터(`fixtureFeaturePrint`)를 준다.
  static func featurePrinter(
    idsByWidth: [Int: ImageAsset.ID],
    failures: FailingIDs,
    analysis: Later<ImageAnalysisClientFake>,
    onFeaturePrint: @escaping @Sendable (ImageAsset.ID, ImageAnalysisClientFake?) async -> Void
  ) -> @Sendable (AnalysisImage) async -> Result<ImageFeaturePrint, ImageAnalysisError> {
    { image in
      let id = idsByWidth[image.cgImage.width] ?? ""
      await onFeaturePrint(id, analysis.current)
      if failures.contains(id) || analysis.current?.isFeaturePrintAvailable == false {
        return .failure(.failed)
      }
      return .success(fixtureFeaturePrint(width: image.cgImage.width))
    }
  }

  static var seoulCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
    return calendar
  }
}
