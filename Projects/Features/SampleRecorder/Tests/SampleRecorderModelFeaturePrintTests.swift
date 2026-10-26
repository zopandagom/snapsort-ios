#if DEBUG
  import Core
  import Foundation
  import ImageAnalysisInterface
  import ImageAnalysisTesting
  import PhotoLibraryInterface
  import PhotoLibraryTesting
  import Testing
  @testable import SampleRecorderFeature

  /// 기록 도구가 운영 1단계처럼 비슷한 사진 대상의 특징 벡터 시간을 재는지 (docs/ARCHITECTURE.md §4 기록 도구).
  @MainActor
  struct SampleRecorderModelFeaturePrintTests {
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("대상 사진은 분류 뒤 같은 썸네일로 특징 벡터를 만들고 원본 로드 전에 시간을 잰다")
    func measuresFeaturePrintAfterClassify() async throws {
      let fixture = RecorderFixture(
        album: [.stub(id: "photo", creationDate: Self.date)],
        isFeaturePrintAvailable: true
      )

      await fixture.record(.accuracy)

      #expect(fixture.log.all == [
        "load:photo:thumbnail",
        "classify:photo",
        "featurePrint:photo",
        "load:photo:largest",
        "ocr:photo",
      ])
      let images = try #require(try jsonObject(fixture.model.phase.result?.timingFile)["images"] as? [[String: Any]])
      #expect(images[0]["featurePrintMs"] is Double)
    }

    @Test("스크린샷·생성일 없음·OCR 대상·대체 버전 썸네일이면 특징 벡터를 요청하지 않는다")
    func skipsNonTargets() async throws {
      let fixture = RecorderFixture(
        album: [
          .stub(id: "shot", creationDate: Self.date, isScreenshot: true),
          .stub(id: "undated"),
          .stub(id: "text", creationDate: Self.date),
          .stub(id: "cloud", creationDate: Self.date),
        ],
        labels: ["text": [ImageLabel(identifier: "document", confidence: 0.9)]],
        fallbackIDs: ["cloud"],
        isFeaturePrintAvailable: true
      )

      await fixture.record(.accuracy)

      #expect(!fixture.log.all.contains { $0.hasPrefix("featurePrint:") })
      #expect(!fixture.imageAnalysis.requests.contains(.featurePrint))
      let images = try #require(try jsonObject(fixture.model.phase.result?.timingFile)["images"] as? [[String: Any]])
      #expect(images.allSatisfy { $0["featurePrintMs"] == nil })
    }

    @Test("특징 벡터를 만들 수 없는 기기면 요청하지 않는다")
    func skipsWhenUnavailable() async throws {
      let fixture = RecorderFixture(album: [.stub(id: "photo", creationDate: Self.date)])

      await fixture.record(.accuracy)

      #expect(!fixture.imageAnalysis.requests.contains(.featurePrint))
      let images = try #require(try jsonObject(fixture.model.phase.result?.timingFile)["images"] as? [[String: Any]])
      #expect(images[0]["featurePrintMs"] == nil)
    }

    @Test("특징 벡터가 실패해도 이미지를 건너뛰지 않고 시간만 비운다")
    func keepsImageWhenFeaturePrintFails() async throws {
      let fixture = RecorderFixture(
        album: [.stub(id: "photo", creationDate: Self.date)],
        isFeaturePrintAvailable: true,
        featurePrintFailures: ["photo"]
      )

      await fixture.record(.accuracy)

      let result = try #require(fixture.model.phase.result)
      #expect(result.skipped.isEmpty)
      #expect(result.recordedSampleCount == 1)
      let images = try #require(try jsonObject(result.timingFile)["images"] as? [[String: Any]])
      #expect(images[0]["outcome"] as? String == "recorded")
      #expect(images[0]["featurePrintMs"] == nil)
      #expect(images[0]["pipelineMs"] is Double)
    }

    @Test("운영 시간(pipelineMs)에 잰 특징 벡터 시간을 1단계로 더한다")
    func pipelineIncludesFeaturePrint() {
      var measurement = ImageMeasurement(index: 0, asset: .stub(id: "photo", creationDate: Self.date))
      measurement.thumbnailLoadMs = 1
      measurement.classifyMs = 2
      #expect(SampleRecording.pipelineMs(of: measurement, needsText: false) == 3)
      measurement.featurePrintMs = 4
      #expect(SampleRecording.pipelineMs(of: measurement, needsText: false) == 7)
      measurement.largestLoadMs = 8
      measurement.ocrMs = 16
      #expect(SampleRecording.pipelineMs(of: measurement, needsText: true) == 31)
    }
  }
#endif
