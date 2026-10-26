// Debug 전용: SampleRecorderModel.swift 머리 주석 참고
#if DEBUG
  import Core
  import Foundation
  import ImageAnalysisInterface
  import PhotoLibraryInterface

  extension SampleRecording {
    /// 썸네일을 읽어 기록 하한으로 분류한다. 특징 벡터가 같은 썸네일을 쓰도록 썸네일도 돌려준다.
    func classify(
      _ asset: ImageAsset,
      measurement: inout ImageMeasurement,
      stage: inout SkippedImage.Stage,
      clock: ContinuousClock
    ) async throws(MeasureStop) -> (AnalysisImage, [ImageLabel]) {
      stage = .thumbnailLoad
      var stepStart = clock.now
      let thumbnail = try await self.loadImage(asset.id, size: .thumbnail)
      measurement.thumbnailLoadMs = stepStart.duration(to: clock.now).milliseconds
      measurement.thumbnailPixelWidth = thumbnail.cgImage.width
      measurement.thumbnailPixelHeight = thumbnail.cgImage.height
      measurement.thumbnailFallback = thumbnail.isLocalFallback

      stage = .classify
      stepStart = clock.now
      let labels = try await self.analysis { () async throws(ImageAnalysisError) in
        try await self.imageAnalysis.classify(thumbnail, minimumConfidence: Self.labelRecordingFloor)
      }
      measurement.classifyMs = stepStart.duration(to: clock.now).milliseconds
      measurement.labelCount = labels.count
      return (thumbnail, labels)
    }

    /// 운영 1단계처럼 비슷한 사진 대상(`ImageFeaturePrint.isTarget`)이고 이 기기에서 벡터를 만들 수 있고 대체 버전이 아니면
    /// 같은 썸네일로 특징 벡터를 만들어 시간을 잰다. 실패(시한 초과 포함)해도 이미지를 건너뛰지 않고 시간을 비워 둔다. 벡터 값은 남기지 않는다.
    func measureFeaturePrint(
      _ thumbnail: AnalysisImage,
      asset: ImageAsset,
      needsText: Bool,
      measurement: inout ImageMeasurement
    ) async throws(MeasureStop) {
      let clock = ContinuousClock()
      guard ImageFeaturePrint.isTarget(asset, needsTextRecognition: needsText),
            self.imageAnalysis.isFeaturePrintAvailable,
            !thumbnail.isLocalFallback
      else { return }
      let stepStart = clock.now
      do throws(ImageAnalysisError) {
        _ = try await self.imageAnalysis.featurePrint(thumbnail)
        measurement.featurePrintMs = stepStart.duration(to: clock.now).milliseconds
      } catch {
        switch error {
        case .cancelled: throw .cancelled
        case .failed: break
        }
      }
    }
  }
#endif
