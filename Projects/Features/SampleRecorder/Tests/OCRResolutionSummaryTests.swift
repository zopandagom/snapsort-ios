#if DEBUG
  import Core
  import Foundation
  import PhotoLibraryTesting
  import Testing
  @testable import SampleRecorderFeature

  /// OCR 해상도 비교 요약. 상한 두 개(A·B)로 이미지별 기록을 직접 만들어 넣는다.
  struct OCRResolutionSummaryTests {
    let caps = [OCRResolutionCap(name: "A", maxPixelCount: 100), OCRResolutionCap(name: "B", maxPixelCount: 50)]

    @Test("같은 입력·실패는 정확도 통계에서 빠지고 따로 세며, 분류 불일치·날짜/숫자를 놓친 이미지 수를 센다")
    func countsStatusesAndMisses() {
      let summary = OCRResolutionSummary.make(
        from: [
          .compared(index: 0, baselineMs: 100, chars: 10, variants: [
            .downscaled("A", ocrMs: 50, matched: 9),
            .init(cap: "B", status: .sameInput),
          ]),
          .compared(index: 1, baselineMs: 100, chars: 10, dates: 1, variants: [
            .downscaled("A", ocrMs: 50, matched: 10, categoryMatches: false, missingDates: 1),
            .init(cap: "B", status: .downscaleFailed),
          ]),
          .compared(index: 2, baselineMs: 100, chars: 10, longNumbers: 2, variants: [
            .init(cap: "A", status: .ocrFailed),
            .downscaled("B", ocrMs: 30, matched: 8, missingLongNumbers: 1),
          ]),
        ],
        caps: self.caps
      )

      let capA = summary.caps[0]
      #expect(capA.name == "A")
      #expect(capA.maxPixelCount == 100)
      #expect((capA.downscaledCount, capA.sameInputCount, capA.failedCount) == (2, 0, 1))
      #expect(capA.categoryMismatchCount == 1)
      #expect((capA.fewerDatesImageCount, capA.imagesWithDatesCount) == (1, 1))
      #expect((capA.fewerLongNumbersImageCount, capA.imagesWithLongNumbersCount) == (0, 0))
      #expect(capA.charRecall?.count == 2)
      let capB = summary.caps[1]
      #expect((capB.downscaledCount, capB.sameInputCount, capB.failedCount) == (1, 1, 1))
      #expect(capB.categoryMismatchCount == 0)
      #expect((capB.fewerLongNumbersImageCount, capB.imagesWithLongNumbersCount) == (1, 1))
      #expect(capB.charRecall?.count == 1)
    }

    @Test("워밍업 이미지는 시간 통계에서만 빠지고, 공통 합계는 모든 상한이 같은 이미지 집합이며 같은 입력은 기준 시간으로 더한다")
    func excludesWarmupAndSumsCommonSet() {
      let summary = OCRResolutionSummary.make(
        from: [
          .compared(index: 0, baselineMs: 1000, chars: 10, variants: [
            .downscaled("A", ocrMs: 500, matched: 10),
            .init(cap: "B", status: .sameInput),
          ]),
          .compared(index: 1, baselineMs: 100, chars: 10, variants: [
            .downscaled("A", ocrMs: 50, matched: 10),
            .init(cap: "B", status: .sameInput),
          ]),
          .compared(index: 2, baselineMs: 200, chars: 10, variants: [
            .downscaled("A", ocrMs: 120, matched: 10),
            .downscaled("B", ocrMs: 80, matched: 10),
          ]),
          // 상한 하나라도 실패하면 공통 집합에서 빠진다.
          .compared(index: 3, baselineMs: 300, chars: 10, variants: [
            .init(cap: "A", status: .ocrFailed),
            .init(cap: "B", status: .sameInput),
          ]),
        ],
        caps: self.caps
      )

      #expect(summary.warmupImageIndex == 0)
      #expect(summary.baseline.ocr?.count == 3)
      #expect(summary.baseline.ocr?.maxMs == 300)
      #expect(summary.baseline.commonTotalMs == 300)
      let capA = summary.caps[0]
      #expect(capA.downscaledCount == 3)
      #expect(capA.ocr == Stats(count: 2, meanMs: 85, p50Ms: 50, p95Ms: 120, maxMs: 120))
      #expect(capA.timeRatio == RatioStats(count: 2, mean: 0.55, p50: 0.5, p95: 0.6))
      #expect(capA.commonCount == 2)
      #expect(capA.commonTotalMs == 170)
      let capB = summary.caps[1]
      #expect(capB.commonCount == 2)
      #expect(capB.commonTotalMs == 180)
    }

    @Test("합산 재현율은 글자 수로 무게를 두어 이미지별 평균과 다르고, 기준 글자가 없는 이미지는 빠진다")
    func pooledRecallWeightsByCharacters() throws {
      let recall = try #require(RecallStats.make([(1, 2), (99, 100), (20, 20), (0, 0)]))

      #expect(recall.count == 3)
      #expect(recall.matchedCharTotal == 120)
      #expect(recall.baselineCharTotal == 122)
      #expect(recall.pooled == 120.0 / 122.0)
      #expect(abs(recall.mean - (0.5 + 0.99 + 1) / 3) < 1e-12)
      #expect(recall.min == 0.5)
      #expect(RecallStats.make([(0, 0)]) == nil)
    }

    @Test("하위 5% 와 시간 비율 백분위는 최근접 순위로 고른다")
    func lowPercentilesUseNearestRank() throws {
      // 40장이면 하위 5% 는 ceil(2) - 1 = 1번째(두 번째로 낮은 값)다.
      let recall = try #require(RecallStats.make((1 ... 40).map { ($0, 40) }))
      #expect(recall.p05 == 2.0 / 40)
      #expect(recall.min == 1.0 / 40)

      let ratio = try #require(RatioStats.make((1 ... 20).map { Double($0) }))
      #expect(ratio == RatioStats(count: 20, mean: 10.5, p50: 10, p95: 19))
      #expect(RatioStats.make([]) == nil)
    }

    @Test("요약의 재현율은 이미지별 일치 수와 기준 글자 수로 계산한다")
    func summaryRecallFromRecords() throws {
      let summary = OCRResolutionSummary.make(
        from: [
          .compared(index: 0, baselineMs: 10, chars: 2, variants: [.downscaled("A", ocrMs: 5, matched: 1)]),
          .compared(index: 1, baselineMs: 10, chars: 100, variants: [.downscaled("A", ocrMs: 5, matched: 99)]),
          .compared(index: 2, baselineMs: 10, chars: 0, variants: [.downscaled("A", ocrMs: 5, matched: 0)]),
        ],
        caps: [self.caps[0]]
      )

      let recall = try #require(summary.caps[0].charRecall)
      #expect(recall.count == 2)
      #expect(recall.pooled == 100.0 / 102.0)
      #expect(recall.min == 0.5)
    }

    @Test("OCR 대상 수는 비교·대체 버전·건너뜀의 합이고, 대체 버전이어도 기준 OCR 이 실패하면 건너뜀이다")
    func countsTargets() {
      var fallbackFailed = ImageMeasurement.skippedTarget(index: 3, stage: .ocr)
      fallbackFailed.ocrFallback = true
      let summary = OCRResolutionSummary.make(
        from: [
          .recorded(index: 0, thumbnail: 10, classify: 20, needsText: false),
          .compared(index: 1, baselineMs: 10, chars: 1, variants: [.init(cap: "A", status: .sameInput)]),
          .fallback(index: 2),
          fallbackFailed,
          .skippedTarget(index: 4, stage: .largestLoad),
          .skipped(index: 5, reason: .analysisFailed),
        ],
        caps: [self.caps[0]]
      )

      #expect(summary.targetCount == 4)
      #expect(summary.comparedCount == 1)
      #expect(summary.fallbackCount == 1)
      #expect(summary.skippedTargetCount == 2)
      #expect(summary.targetCount == summary.comparedCount + summary.fallbackCount + summary.skippedTargetCount)
    }

    @Test("비교한 이미지가 없으면 통계가 없고 개수는 0이다")
    func emptyComparison() {
      let summary = OCRResolutionSummary.make(from: [.fallback(index: 0)], caps: self.caps)

      #expect(summary.comparedCount == 0)
      #expect(summary.warmupImageIndex == nil)
      #expect(summary.baseline == .init(ocr: nil, commonTotalMs: 0))
      for cap in summary.caps {
        #expect((cap.downscaledCount, cap.sameInputCount, cap.failedCount, cap.commonCount) == (0, 0, 0, 0))
        #expect(cap.ocr == nil)
        #expect(cap.timeRatio == nil)
        #expect(cap.charRecall == nil)
        #expect(cap.commonTotalMs == 0)
      }
    }
  }

  extension ImageMeasurement {
    /// 기준과 낮은 상한을 비교한 OCR 대상.
    static func compared(
      index: Int,
      baselineMs: Double,
      chars: Int,
      dates: Int = 0,
      longNumbers: Int = 0,
      variants: [OCRVariantRecord]
    ) -> ImageMeasurement {
      var measurement = ImageMeasurement.recorded(
        index: index,
        thumbnail: 10,
        classify: 20,
        largest: 100,
        ocr: baselineMs,
        needsText: true
      )
      measurement.ocrComparison = OCRComparisonRecord(
        status: .compared,
        baselineOrder: 0,
        baselineCharCount: chars,
        baselineDateCount: dates,
        baselineLongNumberCount: longNumbers,
        variants: variants
      )
      return measurement
    }

    /// 원본이 대체 버전이라 기준 OCR 만 한 OCR 대상.
    static func fallback(index: Int) -> ImageMeasurement {
      var measurement = ImageMeasurement.recorded(
        index: index,
        thumbnail: 10,
        classify: 20,
        largest: 100,
        ocr: 100,
        needsText: true
      )
      measurement.ocrFallback = true
      measurement.ocrComparison = OCRComparisonRecord(status: .fallback)
      return measurement
    }

    /// 원본 로드나 기준 OCR 에 실패해 건너뛴 OCR 대상.
    static func skippedTarget(index: Int, stage: SkippedImage.Stage) -> ImageMeasurement {
      var measurement = ImageMeasurement.skipped(index: index, reason: .analysisFailed)
      measurement.needsTextRecognition = true
      measurement.failedStage = stage
      return measurement
    }
  }

  extension OCRVariantRecord {
    static func downscaled(
      _ cap: String,
      ocrMs: Double,
      matched: Int,
      categoryMatches: Bool = true,
      missingDates: Int = 0,
      missingLongNumbers: Int = 0
    ) -> OCRVariantRecord {
      var record = OCRVariantRecord(cap: cap, status: .downscaled)
      record.ocrMs = ocrMs
      record.matchedCharCount = matched
      record.categoryMatches = categoryMatches
      record.missingDateCount = missingDates
      record.missingLongNumberCount = missingLongNumbers
      return record
    }
  }
#endif
