// Debug 전용: SampleRecorderModel.swift 머리 주석 참고
#if DEBUG
  import Foundation

  /// OCR 해상도 비교 요약. 화면과 측정 파일의 `ocrResolution.summary` 가 함께 쓴다.
  /// 정확도 지표는 정답이 아니라 기준(현재 상한) OCR 대비다.
  /// 개수는 `targetCount == comparedCount + fallbackCount + skippedTargetCount` 다.
  public struct OCRResolutionSummary: Sendable, Equatable, Encodable {
    public struct Baseline: Sendable, Equatable, Encodable {
      /// 비교한 이미지의 기준 OCR 시간(워밍업 제외).
      public let ocr: Stats?
      /// 공통 집합(`CapSummary.commonTotalMs`)의 기준 OCR 시간 합.
      public let commonTotalMs: Double
    }

    /// 상한 하나의 요약. 정확도·시간 지표의 분모는 줄여서 다시 OCR 한(`downscaled`) 이미지다.
    public struct CapSummary: Sendable, Equatable, Encodable {
      public let name: String
      public let maxPixelCount: Int
      public let downscaledCount: Int
      public let sameInputCount: Int
      /// 줄이기 실패 + 변형 OCR 실패.
      public let failedCount: Int
      /// 공통 집합(비교한 이미지 중 어느 상한도 실패하지 않은 이미지, 워밍업 제외)의 수.
      public let commonCount: Int
      /// 변형 OCR 시간(워밍업 제외).
      public let ocr: Stats?
      /// 이미지마다 변형 OCR ms / 기준 OCR ms(워밍업 제외). 발열 드리프트에 덜 민감하다.
      public let timeRatio: RatioStats?
      /// 공통 집합을 이 상한으로 운영했을 때의 OCR 시간 합(줄였으면 변형, 같은 입력이면 기준 시간).
      public let commonTotalMs: Double
      public let categoryMismatchCount: Int
      /// 기준 글자가 있는 이미지의 글자 재현율.
      public let charRecall: RecallStats?
      public let fewerDatesImageCount: Int
      /// 기준에 날짜가 하나 이상 있는 이미지 수(`fewerDatesImageCount` 의 맥락).
      public let imagesWithDatesCount: Int
      public let fewerLongNumbersImageCount: Int
      public let imagesWithLongNumbersCount: Int
    }

    /// 분류까지 마친 OCR 대상 수.
    public let targetCount: Int
    /// 기준 OCR 까지 성공하고 대체 버전이 아니라 비교한 수.
    public let comparedCount: Int
    /// 원본이 대체 버전이라 기준 OCR 만 한 수.
    public let fallbackCount: Int
    /// OCR 대상인데 원본 로드나 기준 OCR 에 실패해 건너뛴 수(대체 버전이어도 기준 OCR 이 실패하면 여기다).
    public let skippedTargetCount: Int
    /// 시간 통계에서 뺀 이미지(처음 비교한 이미지, Vision 텍스트 모델 로딩)의 처리 순서.
    public let warmupImageIndex: Int?
    public let baseline: Baseline
    /// `OCRResolutionCap.all` 순서.
    public let caps: [CapSummary]

    nonisolated static func make(
      from measurements: [ImageMeasurement],
      caps: [OCRResolutionCap]
    ) -> OCRResolutionSummary {
      let targets = measurements.filter { $0.needsTextRecognition == true }
      let recordedTargets = targets.filter { $0.outcome == .recorded }
      let compared = recordedTargets.filter { $0.ocrComparison?.status == .compared }
      let warmupImageIndex = compared.map(\.index).min()
      let timed = compared.filter { $0.index != warmupImageIndex }
      let common = timed.filter { measurement in
        measurement.ocrComparison?.variants.allSatisfy { $0.status == .downscaled || $0.status == .sameInput } == true
      }
      return OCRResolutionSummary(
        targetCount: targets.count,
        comparedCount: compared.count,
        fallbackCount: recordedTargets.count { $0.ocrComparison?.status == .fallback },
        skippedTargetCount: targets.count { $0.outcome == .skipped },
        warmupImageIndex: warmupImageIndex,
        baseline: Baseline(
          ocr: TimingSummary.stats(timed.compactMap(\.ocrMs)),
          commonTotalMs: common.compactMap(\.ocrMs).reduce(0, +)
        ),
        caps: caps.map { self.capSummary($0, compared: compared, timed: timed, common: common) }
      )
    }

    private nonisolated static func capSummary(
      _ cap: OCRResolutionCap,
      compared: [ImageMeasurement],
      timed: [ImageMeasurement],
      common: [ImageMeasurement]
    ) -> CapSummary {
      let all = CapEntry.entries(of: cap, in: compared)
      let downscaled = all.filter { $0.variant.status == .downscaled }
      let timedDownscaled = CapEntry.entries(of: cap, in: timed).filter { $0.variant.status == .downscaled }
      let ratios = timedDownscaled.compactMap { entry -> Double? in
        guard let variantMs = entry.variant.ocrMs, let baselineMs = entry.baselineMs, baselineMs > 0 else { return nil }
        return variantMs / baselineMs
      }
      let commonTotalMs = CapEntry.entries(of: cap, in: common).reduce(0.0) { total, entry in
        total + ((entry.variant.status == .downscaled ? entry.variant.ocrMs : entry.baselineMs) ?? 0)
      }
      let recalls = downscaled.compactMap { entry -> (matched: Int, baseline: Int)? in
        guard let baseline = entry.record.baselineCharCount, let matched = entry.variant.matchedCharCount else {
          return nil
        }
        return (matched, baseline)
      }
      return CapSummary(
        name: cap.name,
        maxPixelCount: cap.maxPixelCount,
        downscaledCount: downscaled.count,
        sameInputCount: all.count { $0.variant.status == .sameInput },
        failedCount: all.count { $0.variant.status == .downscaleFailed || $0.variant.status == .ocrFailed },
        commonCount: common.count,
        ocr: TimingSummary.stats(timedDownscaled.compactMap(\.variant.ocrMs)),
        timeRatio: RatioStats.make(ratios),
        commonTotalMs: commonTotalMs,
        categoryMismatchCount: downscaled.count { $0.variant.categoryMatches == false },
        charRecall: RecallStats.make(recalls),
        fewerDatesImageCount: downscaled.count { ($0.variant.missingDateCount ?? 0) > 0 },
        imagesWithDatesCount: downscaled.count { ($0.record.baselineDateCount ?? 0) > 0 },
        fewerLongNumbersImageCount: downscaled.count { ($0.variant.missingLongNumberCount ?? 0) > 0 },
        imagesWithLongNumbersCount: downscaled.count { ($0.record.baselineLongNumberCount ?? 0) > 0 }
      )
    }
  }

  /// 비교한 이미지 하나에서 상한 하나의 기록.
  private struct CapEntry {
    let baselineMs: Double?
    let record: OCRComparisonRecord
    let variant: OCRVariantRecord

    nonisolated static func entries(of cap: OCRResolutionCap, in measurements: [ImageMeasurement]) -> [CapEntry] {
      measurements.compactMap { measurement in
        guard
          let record = measurement.ocrComparison,
          let variant = record.variants.first(where: { $0.cap == cap.name })
        else { return nil }
        return CapEntry(baselineMs: measurement.ocrMs, record: record, variant: variant)
      }
    }
  }

  /// 비율 값 묶음의 요약. p50·p95 는 `TimingSummary.stats` 와 같은 최근접 순위다.
  public struct RatioStats: Sendable, Equatable, Encodable {
    public let count: Int
    public let mean: Double
    public let p50: Double
    public let p95: Double

    /// 값이 없으면 nil.
    nonisolated static func make(_ values: [Double]) -> RatioStats? {
      guard !values.isEmpty else { return nil }
      let sorted = values.sorted()
      return RatioStats(
        count: sorted.count,
        mean: sorted.reduce(0, +) / Double(sorted.count),
        p50: nearestRank(sorted, 0.5),
        p95: nearestRank(sorted, 0.95)
      )
    }
  }

  /// 글자 재현율 요약. `pooled` 는 글자 수로 무게를 둔 합산 값(`Σ matched / Σ baseline`)이고,
  /// `mean`·`p05`·`min` 은 이미지별 재현율 분포(놓치는 이미지가 있는지)다.
  public struct RecallStats: Sendable, Equatable, Encodable {
    public let count: Int
    public let matchedCharTotal: Int
    public let baselineCharTotal: Int
    public let pooled: Double
    public let mean: Double
    /// 낮은 쪽 5% 를 최근접 순위로 고른 값.
    public let p05: Double
    public let min: Double

    /// 기준 글자가 있는 이미지가 없으면 nil.
    nonisolated static func make(_ pairs: [(matched: Int, baseline: Int)]) -> RecallStats? {
      let valid = pairs.filter { $0.baseline > 0 }
      guard !valid.isEmpty else { return nil }
      let matchedTotal = valid.reduce(0) { $0 + $1.matched }
      let baselineTotal = valid.reduce(0) { $0 + $1.baseline }
      let sorted = valid.map { Double($0.matched) / Double($0.baseline) }.sorted()
      return RecallStats(
        count: sorted.count,
        matchedCharTotal: matchedTotal,
        baselineCharTotal: baselineTotal,
        pooled: Double(matchedTotal) / Double(baselineTotal),
        mean: sorted.reduce(0, +) / Double(sorted.count),
        p05: nearestRank(sorted, 0.05),
        min: sorted[0]
      )
    }
  }

  /// 오름차순으로 정렬한 값에서 `ceil(p·n) - 1` 번째(최근접 순위). `TimingSummary.stats` 와 같은 규칙이다.
  private nonisolated func nearestRank(_ sorted: [Double], _ fraction: Double) -> Double {
    sorted[max(Int((fraction * Double(sorted.count)).rounded(.up)) - 1, 0)]
  }
#endif
