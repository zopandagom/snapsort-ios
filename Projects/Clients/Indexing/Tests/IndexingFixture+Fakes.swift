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

  static var seoulCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
    return calendar
  }
}
