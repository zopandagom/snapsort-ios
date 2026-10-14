#if DEBUG
  import Core
  import Foundation
  import PhotoLibraryTesting
  import Testing
  @testable import SampleRecorderFeature

  struct TimingSummaryTests {
    @Test("값이 없으면 요약하지 않는다")
    func statsOfNothingIsNil() {
      #expect(TimingSummary.stats([]) == nil)
    }

    @Test(
      "평균·최대와 최근접 순위의 p50·p95 를 고른다",
      arguments: [
        ([7.0] as [Double], Stats(count: 1, meanMs: 7, p50Ms: 7, p95Ms: 7, maxMs: 7)),
        ([4.0, 2], Stats(count: 2, meanMs: 3, p50Ms: 2, p95Ms: 4, maxMs: 4)),
        ([5.0, 1, 3], Stats(count: 3, meanMs: 3, p50Ms: 3, p95Ms: 5, maxMs: 5)),
        ((1 ... 20).map { Double($0) }, Stats(count: 20, meanMs: 10.5, p50Ms: 10, p95Ms: 19, maxMs: 20)),
      ]
    )
    func computesStats(values: [Double], expected: Stats) {
      #expect(TimingSummary.stats(values) == expected)
    }

    @Test("분류까지 마친 이미지가 없으면 OCR 대상 비율이 없다")
    func ocrTargetRatioWithoutClassifiedImages() {
      let summary = TimingSummary.make(
        from: [.skipped(index: 0, reason: .unavailable)],
        thermalChanges: [ThermalStateChange(index: 0, state: .nominal)]
      )

      #expect(summary.ocrTargetRatio == nil)
      #expect(summary.ocrTargetCount == 0)
      #expect(summary.pipeline == nil)
      #expect(summary.firstImagePipelineMs == nil)
    }

    @Test("pipeline 은 OCR 대상이 아닌 이미지의 원본·OCR 시간을 빼고 건너뛴 이미지는 넣지 않는다")
    func pipelineFollowsProductionStages() {
      let summary = TimingSummary.make(
        from: [
          .recorded(index: 0, thumbnail: 10, classify: 20, largest: 100, ocr: 200, needsText: false),
          .recorded(index: 1, thumbnail: 10, classify: 20, largest: 100, ocr: 200, needsText: true),
          .skipped(index: 2, reason: .analysisFailed),
        ],
        thermalChanges: [ThermalStateChange(index: 0, state: .nominal)]
      )

      #expect(summary.pipeline == Stats(count: 2, meanMs: 180, p50Ms: 30, p95Ms: 330, maxMs: 330))
      #expect(summary.ocr?.count == 2)
      #expect(summary.ocrTargetCount == 1)
      #expect(summary.ocrTargetRatio == 0.5)
      #expect(summary.skipped == .init(unavailable: 0, gone: 0, analysisFailed: 1))
    }

    @Test("첫 이미지 pipeline 은 처음 기록한 이미지의 값이다")
    func reportsFirstImagePipeline() {
      let summary = TimingSummary.make(
        from: [
          .skipped(index: 0, reason: .gone),
          .recorded(index: 1, thumbnail: 300, classify: 400, needsText: false),
          .recorded(index: 2, thumbnail: 10, classify: 20, needsText: false),
        ],
        thermalChanges: [ThermalStateChange(index: 0, state: .nominal)]
      )

      #expect(summary.firstImagePipelineMs == 700)
    }

    @Test("OCR 대상이 없는 속도 결과도 인코딩되고 원본·OCR 요약 키가 없다")
    func encodesSummaryWithoutOCR() throws {
      let summary = TimingSummary.make(
        from: [.recorded(index: 0, thumbnail: 10, classify: 20, needsText: false)],
        thermalChanges: [ThermalStateChange(index: 0, state: .nominal)]
      )

      let file = try #require(RecordingOutput.encode(summary, fileName: "summary.json").file)
      let object = try #require(try JSONSerialization.jsonObject(with: file.data) as? [String: Any])

      #expect(object["ocr"] == nil)
      #expect(object["largestLoad"] == nil)
      #expect(object["ocrTargetRatio"] as? Double == 0)
      #expect(object["pipeline"] != nil)
    }
  }

  extension ImageMeasurement {
    static func recorded(
      index: Int,
      thumbnail: Double,
      classify: Double,
      largest: Double? = nil,
      ocr: Double? = nil,
      needsText: Bool
    ) -> ImageMeasurement {
      var measurement = ImageMeasurement(index: index, asset: .stub(id: "image-\(index)"))
      measurement.thumbnailLoadMs = thumbnail
      measurement.classifyMs = classify
      measurement.needsTextRecognition = needsText
      measurement.largestLoadMs = largest
      measurement.ocrMs = ocr
      measurement.pipelineMs = SampleRecording.pipelineMs(of: measurement, needsText: needsText)
      measurement.totalMs = thumbnail + classify + (largest ?? 0) + (ocr ?? 0)
      return measurement
    }

    static func skipped(index: Int, reason: SkippedImage.Reason) -> ImageMeasurement {
      var measurement = ImageMeasurement(index: index, asset: .stub(id: "image-\(index)"))
      measurement.outcome = .skipped
      measurement.skipReason = reason
      measurement.failedStage = .thumbnailLoad
      return measurement
    }
  }
#endif
