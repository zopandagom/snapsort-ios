// Debug 전용: SampleRecorderModel.swift 머리 주석 참고
#if DEBUG
  import Core
  import Foundation
  import ImageAnalysisInterface
  import PhotoLibraryInterface

  /// OCR 해상도 비교 모드의 한 장 측정. `SampleRecording.measure` 가 OCR 대상일 때 부른다.
  /// 단계 내용은 `SampleRecording` 문서 주석의 규칙(인덱서 `IndexingRun.classify`·`IndexingRun.recognize` 와 같은 단계)을 따른다.
  extension SampleRecording {
    /// 원본(기준)을 읽고 기준과 낮은 상한(`OCRResolutionCap.all`)을 `OCRResolution.variantOrder` 순서로 OCR 한 뒤 기준 대비 지표를 남긴다.
    /// `measurement` 의 원본·OCR 필드는 기준 값이라 pipeline 은 속도 모드와 같은 의미다. 텍스트는 지표를 계산한 뒤 버린다.
    /// - 원본이 대체 버전이면 기준 OCR 만 하고(속도 모드와 같다) 비교하지 않는다.
    /// - 기준 OCR 이 실패하면 이미 끝낸 낮은 상한 결과를 버리고 이미지를 건너뛴다(stage `ocr`).
    /// - 낮은 상한의 줄이기·OCR 실패는 그 상한만 실패로 기록하고 다음 상한을 계속한다.
    /// - 취소는 줄이기 앞뒤와 OCR 에서 확인해, 이미지를 남기지 않고 멈춘다.
    func compareResolutions(
      _ asset: ImageAsset,
      index: Int,
      ruleLabels: [ImageLabel],
      measurement: inout ImageMeasurement,
      stage: inout SkippedImage.Stage
    ) async throws(MeasureStop) {
      let clock = ContinuousClock()
      stage = .largestLoad
      let loadStart = clock.now
      let image = try await self.loadImage(asset.id, size: .largestAvailable)
      measurement.largestLoadMs = loadStart.duration(to: clock.now).milliseconds
      measurement.ocrPixelWidth = image.cgImage.width
      measurement.ocrPixelHeight = image.cgImage.height
      measurement.ocrFallback = image.isLocalFallback

      stage = .ocr
      guard !image.isLocalFallback else {
        let textLines = try await self.recognizeBaseline(image, measurement: &measurement, clock: clock)
        measurement.textLineCount = textLines.count
        measurement.ocrComparison = OCRComparisonRecord(status: .fallback)
        return
      }

      var texts = OCRComparisonTexts(caps: OCRResolutionCap.all)
      for position in OCRResolution.variantOrder(index: index, variantCount: texts.caps.count + 1) {
        if position == 0 {
          texts.baselineOrder = texts.ocrCount
          texts.ocrCount += 1
          texts.baselineLines = try await self.recognizeBaseline(image, measurement: &measurement, clock: clock)
          measurement.textLineCount = texts.baselineLines.count
        } else {
          try await self.recognizeVariant(of: image, capIndex: position - 1, texts: &texts, clock: clock)
        }
      }
      // 모든 OCR 이 끝난 뒤 메모리 안 텍스트로 지표를 계산하고, 기록에는 숫자만 남긴다.
      measurement.ocrComparison = texts.record(asset: asset, ruleLabels: ruleLabels)
    }

    /// 기준 OCR. 실패하면 속도 모드처럼 이미지를 건너뛴다.
    private func recognizeBaseline(
      _ image: AnalysisImage,
      measurement: inout ImageMeasurement,
      clock: ContinuousClock
    ) async throws(MeasureStop) -> [RecognizedTextLine] {
      let start = clock.now
      let textLines = try await self.analysis { () async throws(ImageAnalysisError) in
        try await self.imageAnalysis.recognizeText(image)
      }
      measurement.ocrMs = start.duration(to: clock.now).milliseconds
      return textLines
    }

    /// 낮은 상한 하나. 같은 입력이면 OCR 하지 않고, 줄이기·OCR 실패는 그 상한만 실패로 남긴다. 취소면 이미지를 멈춘다.
    private func recognizeVariant(
      of image: AnalysisImage,
      capIndex: Int,
      texts: inout OCRComparisonTexts,
      clock: ContinuousClock
    ) async throws(MeasureStop) {
      let cap = texts.caps[capIndex]
      guard
        let size = OCRResolution.downscaledSize(
          width: image.cgImage.width,
          height: image.cgImage.height,
          maxPixelCount: cap.maxPixelCount
        )
      else { return }
      if Task.isCancelled {
        throw .cancelled
      }
      let scaled = OCRResolution.downscale(image, to: size)
      if Task.isCancelled {
        throw .cancelled
      }
      guard let scaled else {
        texts.variants[capIndex] = OCRVariantRecord(cap: cap.name, status: .downscaleFailed)
        return
      }
      var variant = OCRVariantRecord(cap: cap.name, status: .downscaled)
      variant.order = texts.ocrCount
      variant.pixelWidth = size.width
      variant.pixelHeight = size.height
      texts.ocrCount += 1
      let start = clock.now
      do throws(ImageAnalysisError) {
        let lines = try await self.imageAnalysis.recognizeText(scaled)
        variant.ocrMs = start.duration(to: clock.now).milliseconds
        variant.textLineCount = lines.count
        texts.variantLines[capIndex] = lines
      } catch {
        switch error {
        case .cancelled: throw .cancelled
        case .failed: variant.status = .ocrFailed
        }
      }
      texts.variants[capIndex] = variant
    }
  }

  /// 이미지 한 장에서 기준과 낮은 상한을 OCR 하는 동안 모으는 값. 지표를 계산하기 전까지만 텍스트를 들고 있다.
  struct OCRComparisonTexts {
    let caps: [OCRResolutionCap]
    var baselineLines: [RecognizedTextLine] = []
    var baselineOrder = 0
    /// `caps` 순서. 줄이지 않은 상한은 같은 입력으로 남는다.
    var variants: [OCRVariantRecord]
    /// OCR 에 성공한 상한(`caps` 위치)의 줄.
    var variantLines: [Int: [RecognizedTextLine]] = [:]
    /// 이 이미지에서 지금까지 시작한 OCR 수. 다음 OCR 의 순서다.
    var ocrCount = 0

    init(caps: [OCRResolutionCap]) {
      self.caps = caps
      self.variants = caps.map { OCRVariantRecord(cap: $0.name, status: .sameInput) }
    }

    /// 기준 줄 대비 지표(글자 일치 수, 운영 라벨로 분류한 결과 일치, 놓친 날짜·숫자열)를 계산한 기록.
    func record(asset: ImageAsset, ruleLabels: [ImageLabel]) -> OCRComparisonRecord {
      let baselineMetrics = OCRTextMetrics(lines: self.baselineLines.map(\.text))
      let baselineCategories = RuleClassifier.classify(asset: asset, labels: ruleLabels, textLines: self.baselineLines)
      var variants = self.variants
      for (capIndex, lines) in self.variantLines {
        let metrics = OCRTextMetrics(lines: lines.map(\.text))
        variants[capIndex].matchedCharCount = baselineMetrics.matchedCharCount(in: metrics)
        variants[capIndex].categoryMatches =
          RuleClassifier.classify(asset: asset, labels: ruleLabels, textLines: lines) == baselineCategories
        variants[capIndex].missingDateCount = baselineMetrics.missingDates(in: metrics)
        variants[capIndex].missingLongNumberCount = baselineMetrics.missingLongNumbers(in: metrics)
      }
      return OCRComparisonRecord(
        status: .compared,
        baselineOrder: self.baselineOrder,
        baselineCharCount: baselineMetrics.charCount,
        baselineDateCount: baselineMetrics.dateCount,
        baselineLongNumberCount: baselineMetrics.longNumberCount,
        variants: variants
      )
    }
  }
#endif
