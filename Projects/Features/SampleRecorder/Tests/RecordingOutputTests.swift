#if DEBUG
  import Foundation
  import Testing
  @testable import SampleRecorderFeature

  struct RecordingOutputTests {
    @Test(
      "신뢰도는 기준을 넘는 쪽으로 바뀌지 않게 소수 3자리로 내린다",
      arguments: [(Float(0.0996), 0.099), (0.1004, 0.1), (0.9129, 0.912), (0.7, 0.7), (0.01, 0.01)]
    )
    func truncatesConfidence(confidence: Float, expected: Double) {
      #expect(RecordingOutput.truncatedConfidence(confidence) == expected)
    }

    @Test("샘플 초안은 픽스처와 같은 키에 expected 대신 predicted 를 쓴다")
    func sampleDraftKeys() throws {
      let draft = SampleDraft(
        name: "앨범 001",
        asset: .init(isScreenshot: true, hasLocation: false, pixelWidth: 1179, pixelHeight: 2556),
        labels: [.init(identifier: "screenshot", confidence: 0.912)],
        text: ["선물하기"],
        ocrSkipped: nil,
        predicted: ["gifticon"]
      )

      let file = try #require(RecordingOutput.encode([draft], fileName: "draft.json").file)
      let samples = try #require(try JSONSerialization.jsonObject(with: file.data) as? [[String: Any]])
      let sample = try #require(samples.first)
      let asset = try #require(sample["asset"] as? [String: Any])
      let label = try #require((sample["labels"] as? [[String: Any]])?.first)

      #expect(Set(sample.keys) == ["name", "asset", "labels", "text", "predicted"])
      #expect(Set(asset.keys) == ["isScreenshot", "hasLocation", "pixelWidth", "pixelHeight"])
      #expect(Set(label.keys) == ["identifier", "confidence"])
      #expect(label["confidence"] as? Double == 0.912)
    }

    @Test("OCR 하지 않은 샘플만 ocrSkipped 키를 쓴다")
    func sampleDraftOCRSkippedKey() throws {
      let skipped = SampleDraft(
        name: "보관함 00001",
        asset: .init(isScreenshot: false, hasLocation: true, pixelWidth: 4032, pixelHeight: 3024),
        labels: [.init(identifier: "food", confidence: 0.8)],
        text: [],
        ocrSkipped: true,
        predicted: ["food"]
      )

      let file = try #require(RecordingOutput.encode([skipped], fileName: "draft.json").file)
      let sample = try #require(try (JSONSerialization.jsonObject(with: file.data) as? [[String: Any]])?.first)

      #expect(sample["ocrSkipped"] as? Bool == true)
    }

    @Test("유한하지 않은 신뢰도가 들면 그 파일만 만들지 못한다")
    func failsToEncodeNonFiniteConfidence() {
      let draft = SampleDraft(
        name: "앨범 001",
        asset: .init(isScreenshot: false, hasLocation: false, pixelWidth: 1, pixelHeight: 1),
        labels: [.init(identifier: "food", confidence: RecordingOutput.truncatedConfidence(.nan))],
        text: [],
        ocrSkipped: nil,
        predicted: []
      )
      let summary = TimingSummary.make(from: [], thermalChanges: [])

      #expect(RecordingOutput.encode([draft], fileName: "draft.json") == .encodingFailed)
      #expect(RecordingOutput.encode(summary, fileName: "summary.json").file != nil)
    }

    @Test("파일 이름은 모드와 기록 시각(분까지)을 담는다")
    func fileNames() throws {
      let seoul = try #require(TimeZone(identifier: "Asia/Seoul"))
      // 2027-01-15 08:00:00 UTC = 17:00 KST
      let date = Date(timeIntervalSince1970: 1_800_000_000)

      #expect(
        RecordingOutput.samplesFileName(at: date, timeZone: seoul) == "ClassificationSamples-draft-20270115-1700.json"
      )
      #expect(
        RecordingOutput.timingFileName(mode: .accuracy, at: date, timeZone: seoul)
          == "IndexingTiming-accuracy-20270115-1700.json"
      )
      #expect(
        RecordingOutput.timingFileName(mode: .speed(count: 10000), at: date, timeZone: seoul)
          == "IndexingTiming-speed10000-20270115-1700.json"
      )
      #expect(
        RecordingOutput.timingFileName(mode: .ocrResolution(count: 100), at: date, timeZone: seoul)
          == "IndexingTiming-ocrResolution100-20270115-1700.json"
      )
    }
  }
#endif
