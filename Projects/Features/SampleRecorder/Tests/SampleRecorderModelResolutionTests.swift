#if DEBUG
  import Core
  import Foundation
  import ImageAnalysisInterface
  import PhotoLibraryInterface
  import PhotoLibraryTesting
  import Testing
  @testable import SampleRecorderFeature

  /// OCR 해상도 비교 모드. 원본을 줄일 만큼 큰 이미지(`largestImages`)로 주고, OCR Fake 는 입력 크기로 결과를 고른다.
  /// 2,100×1,000(2.1MP)은 2MP·1MP 만, 2,400×1,720(4.1MP)은 4MP·2MP·1MP 가 줄어든다.
  @MainActor
  struct SampleRecorderModelResolutionTests {
    static let twoMP = AnalysisImage.stub(width: 2100, height: 1000)
    static let fourMP = AnalysisImage.stub(width: 2400, height: 1720)

    /// 상한 이름의 줄인 크기를 "폭x높이" 로. 같은 입력이면 nil.
    static func size(of image: AnalysisImage, cap name: String) -> String? {
      self.downscaled(image, cap: name).map { "\($0.width)x\($0.height)" }
    }

    static func downscaled(_ image: AnalysisImage, cap name: String) -> (width: Int, height: Int)? {
      guard
        let cap = OCRResolutionCap.all.first(where: { $0.name == name }),
        let size = OCRResolution.downscaledSize(
          width: image.cgImage.width,
          height: image.cgImage.height,
          maxPixelCount: cap.maxPixelCount
        )
      else { return nil }
      return size
    }

    @Test("최신 N장 중 OCR 대상만 원본을 읽어 비교하고, 대상이 아니면 원본을 읽지 않는다")
    func comparesOnlyTextTargets() async throws {
      let fixture = RecorderFixture(
        library: [
          .stub(id: "shot", isScreenshot: true),
          .stub(id: "meal", coordinate: seoul),
          .stub(id: "later", isScreenshot: true),
        ],
        labels: ["meal": [ImageLabel(identifier: "food", confidence: 0.8)]],
        largestImages: ["shot": Self.twoMP],
        recognizeBySize: { _, _ in .success(["abc"]) }
      )

      await fixture.record(.ocrResolution(count: 2))

      let log = fixture.log.all
      #expect(log.contains("load:shot:largest"))
      #expect(!log.contains("load:meal:largest"))
      #expect(!log.contains { $0.hasPrefix("load:later") })
      let result = try #require(fixture.model.phase.result)
      #expect(fixture.model.phase == .finished(result))
      let images = try #require(try jsonObject(result.timingFile)["images"] as? [[String: Any]])
      #expect(images.count == 2)
      #expect(images[0]["ocrComparison"] != nil)
      #expect(images[1]["ocrComparison"] == nil)
      #expect(result.ocrComparison?.targetCount == 1)
      #expect(result.ocrComparison?.comparedCount == 1)
    }

    @Test("이미지마다 기준을 포함한 OCR 순서가 처리 순서만큼 회전하고, 실제 순서를 기록한다")
    func rotatesOrderPerImage() async throws {
      let fixture = RecorderFixture(
        library: [.stub(id: "a", isScreenshot: true), .stub(id: "b", isScreenshot: true)],
        largestImages: ["a": Self.fourMP, "b": Self.fourMP],
        recognizeBySize: { _, _ in .success([]) }
      )

      await fixture.record(.ocrResolution(count: 2))

      let base = "2400x1720"
      let four = try #require(Self.size(of: Self.fourMP, cap: "4MP"))
      let two = try #require(Self.size(of: Self.fourMP, cap: "2MP"))
      let one = try #require(Self.size(of: Self.fourMP, cap: "1MP"))
      #expect(Self.size(of: Self.fourMP, cap: "8MP") == nil)
      // 0번 이미지: [기준, 8, 4, 2, 1], 1번 이미지: [8, 4, 2, 1, 기준]. 8MP 는 같은 입력이라 OCR 하지 않는다.
      #expect(fixture.log.all.filter { $0.hasPrefix("ocr:") } == [
        base, four, two, one,
        four, two, one, base,
      ].map { "ocr:\($0)" })
      let images = try #require(try jsonObject(fixture.model.phase.result?.timingFile)["images"] as? [[String: Any]])
      let second = try #require(images[1]["ocrComparison"] as? [String: Any])
      #expect(second["baselineOrder"] as? Int == 3)
      let variants = try #require(second["variants"] as? [[String: Any]])
      #expect(variants.map { $0["cap"] as? String } == ["8MP", "4MP", "2MP", "1MP"])
      #expect(variants.map { $0["status"] as? String } == ["sameInput", "downscaled", "downscaled", "downscaled"])
      #expect(variants.map { $0["order"] as? Int } == [nil, 0, 1, 2])
    }

    @Test("모든 상한보다 작은 이미지는 다시 OCR 하지 않고 모든 상한이 같은 입력이다")
    func smallImagesAreSameInput() async throws {
      let fixture = RecorderFixture(library: [.stub(id: "small", isScreenshot: true)], text: ["small": ["abc"]])

      await fixture.record(.ocrResolution(count: 1))

      #expect(fixture.log.all.filter { $0.hasPrefix("ocr:") } == ["ocr:small"])
      let summary = try #require(fixture.model.phase.result?.ocrComparison)
      #expect(summary.comparedCount == 1)
      #expect(summary.caps.map(\.sameInputCount) == [1, 1, 1, 1])
      #expect(summary.caps.map(\.downscaledCount) == [0, 0, 0, 0])
      #expect(summary.caps.allSatisfy { $0.charRecall == nil })
    }

    @Test("낮은 상한 OCR 이 실패하면 그 상한만 실패로 세고 이미지는 기록하며, 기준 OCR 이 실패하면 이미지를 건너뛴다")
    func handlesOCRFailures() async throws {
      let oneMPWidth = try #require(Self.downscaled(Self.twoMP, cap: "1MP")).width
      let fixture = RecorderFixture(
        library: [.stub(id: "variant", isScreenshot: true), .stub(id: "baseline", isScreenshot: true)],
        largestImages: ["variant": Self.twoMP, "baseline": Self.fourMP],
        recognizeBySize: { width, _ in
          // 0번 이미지의 1MP 변형과 1번 이미지의 기준이 실패한다.
          width == oneMPWidth || width == 2400 ? .failure(.failed) : .success(["abc"])
        }
      )

      await fixture.record(.ocrResolution(count: 2))

      let result = try #require(fixture.model.phase.result)
      #expect(result.skipped == [SkippedImage(index: 1, reason: .analysisFailed, stage: .ocr)])
      let images = try #require(try jsonObject(result.timingFile)["images"] as? [[String: Any]])
      #expect(images.map { $0["outcome"] as? String } == ["recorded", "skipped"])
      #expect(images[1]["ocrComparison"] == nil)
      let variants = try #require((images[0]["ocrComparison"] as? [String: Any])?["variants"] as? [[String: Any]])
      #expect(variants.map { $0["status"] as? String } == ["sameInput", "sameInput", "downscaled", "ocrFailed"])
      // 0번 이미지 순서: 기준(0) → 2MP(1) → 1MP(2). 8MP·4MP 는 같은 입력이라 OCR 하지 않는다.
      #expect(variants[3]["order"] as? Int == 2)
      let summary = try #require(result.ocrComparison)
      #expect(summary.caps.map(\.failedCount) == [0, 0, 0, 1])
      #expect((summary.targetCount, summary.comparedCount, summary.skippedTargetCount) == (2, 1, 1))
    }

    @Test("원본이 대체 버전이면 기준 OCR 만 하고 비교하지 않으며, 기준 OCR 이 실패하면 건너뜀으로 센다")
    func doesNotCompareFallbacks() async throws {
      let fixture = RecorderFixture(
        library: [.stub(id: "cloud", isScreenshot: true), .stub(id: "broken", isScreenshot: true)],
        text: ["cloud": ["abc"]],
        fallbackIDs: ["cloud", "broken"],
        recognizeFailures: ["broken"]
      )

      await fixture.record(.ocrResolution(count: 2))

      #expect(fixture.log.all.filter { $0.hasPrefix("ocr:") } == ["ocr:cloud", "ocr:broken"])
      let result = try #require(fixture.model.phase.result)
      let images = try #require(try jsonObject(result.timingFile)["images"] as? [[String: Any]])
      let comparison = try #require(images[0]["ocrComparison"] as? [String: Any])
      #expect(comparison["status"] as? String == "fallback")
      #expect((comparison["variants"] as? [Any])?.isEmpty == true)
      #expect(images[0]["ocrFallback"] as? Bool == true)
      #expect(images[0]["textLineCount"] as? Int == 1)
      let summary = try #require(result.ocrComparison)
      #expect(summary.targetCount == 2)
      #expect(summary.comparedCount == 0)
      #expect(summary.fallbackCount == 1)
      #expect(summary.skippedTargetCount == 1)
    }

    @Test("낮은 상한 OCR 도중 멈추면 그 이미지는 남기지 않고 앞 이미지로 비교 요약을 만든다")
    func cancelsDuringVariantOCR() async throws {
      let started = Flag()
      let twoMPWidth = try #require(Self.downscaled(Self.twoMP, cap: "2MP")).width
      let blocks = ValueSequence([false, true])
      let fixture = RecorderFixture(
        library: (0 ..< 3).map { ImageAsset.stub(id: "shot-\($0)", isScreenshot: true) },
        largestImages: Dictionary(uniqueKeysWithValues: (0 ..< 3).map { ("shot-\($0)", Self.twoMP) }),
        recognizeBySize: { width, _ in
          // 1번 이미지의 2MP 변형 OCR 도중에 붙잡는다.
          if width == twoMPWidth, blocks.next() {
            await waitUntilCancelled(started)
            return .failure(.cancelled)
          }
          return .success(["abc"])
        }
      )
      fixture.model.modeChanged(.ocrResolution(count: 3))
      let start = Task { await fixture.model.startTapped() }
      await waitUntil { started.isSet }

      fixture.model.cancelTapped()
      await start.value

      #expect(fixture.model.phase.cancelReason == .user)
      let result = try #require(fixture.model.phase.result)
      #expect(try jsonObject(result.timingFile)["processedCount"] as? Int == 1)
      #expect(result.ocrComparison?.comparedCount == 1)
      #expect(result.ocrComparison?.targetCount == 1)
      #expect(!fixture.log.all.contains { $0.hasPrefix("load:shot-2") })
    }

    @Test("낮은 상한에서 키워드를 놓치면 운영 라벨로 분류해 불일치로 센다(기록 하한 라벨은 분류에 쓰지 않는다)")
    func countsCategoryMismatch() async throws {
      let fixture = RecorderFixture(
        library: [.stub(id: "gift", isScreenshot: true)],
        // 0.05 coupon 을 쓰면 줄과 관계없이 기프티콘이라 불일치가 생기지 않는다.
        labels: ["gift": [
          ImageLabel(identifier: "screenshot", confidence: 0.9),
          ImageLabel(identifier: "coupon", confidence: 0.05),
        ]],
        largestImages: ["gift": Self.twoMP],
        recognizeBySize: { width, _ in
          width == 2100 ? .success(["선물하기", "유효기간 2026.12.31"]) : .success(["선물하기"])
        }
      )

      await fixture.record(.ocrResolution(count: 1))

      let summary = try #require(fixture.model.phase.result?.ocrComparison)
      #expect(summary.caps.map(\.categoryMismatchCount) == [0, 0, 1, 1])
      #expect(summary.caps.map(\.fewerDatesImageCount) == [0, 0, 1, 1])
      #expect(summary.caps.map(\.imagesWithDatesCount) == [0, 0, 1, 1])
      let recall = try #require(summary.caps[2].charRecall)
      #expect(recall.matchedCharTotal == 4)
      #expect(recall.baselineCharTotal == 4 + 14)
    }

    @Test("측정 파일에 OCR 텍스트·식별자·라벨·카테고리·날짜 값 없이 상한과 요약 숫자만 남긴다")
    func timingFileHasNoPrivateValues() async throws {
      let fixture = RecorderFixture(
        library: [.stub(id: "PRIVATE-ASSET-ID", isScreenshot: true)],
        labels: ["PRIVATE-ASSET-ID": [ImageLabel(identifier: "coupon", confidence: 0.9)]],
        largestImages: ["PRIVATE-ASSET-ID": Self.twoMP],
        recognizeBySize: { width, _ in
          .success(width == 2100 ? ["비밀 쿠폰 번호 9876543210", "유효기간 2031.07.15"] : ["비밀 쿠폰"])
        }
      )

      await fixture.record(.ocrResolution(count: 1))

      let result = try #require(fixture.model.phase.result)
      let file = try #require(result.timingFile.file)
      let text = try #require(String(bytes: file.data, encoding: .utf8))
      for secret in ["PRIVATE-ASSET-ID", "비밀", "9876543210", "2031.07.15", "coupon", ImageCategory.gifticon.rawValue] {
        #expect(!text.contains(secret), "측정 파일에 \(secret) 가 들어 있다")
      }
      let section = try #require(try jsonObject(result.timingFile)["ocrResolution"] as? [String: Any])
      let caps = try #require(section["caps"] as? [[String: Any]])
      #expect(caps.map { $0["name"] as? String } == ["8MP", "4MP", "2MP", "1MP"])
      #expect(caps.map { $0["maxPixelCount"] as? Int } == OCRResolutionCap.all.map(\.maxPixelCount))
      #expect(section["rotation"] is String)
      let summary = try #require(section["summary"] as? [String: Any])
      #expect(summary["comparedCount"] as? Int == 1)
    }

    @Test("이 모드의 파일 이름·mode·요청 수를 남기고 여행 판정 시간은 재지 않는다")
    func recordsModeInTimingFile() async throws {
      let fixture = RecorderFixture(library: .stubs(count: 3))

      await fixture.record(.ocrResolution(count: 1000))

      let result = try #require(fixture.model.phase.result)
      #expect(result.timingFile.file?.fileName == "IndexingTiming-ocrResolution1000-20270115-1700.json")
      #expect(result.samplesFile == nil)
      let timing = try jsonObject(result.timingFile)
      #expect(timing["mode"] as? String == "ocrResolution")
      #expect(timing["requestedCount"] as? Int == 1000)
      #expect(timing["libraryCount"] as? Int == 3)
      #expect(timing["travelDetectionMs"] == nil)
      let limitations = try #require(timing["limitations"] as? [String])
      #expect(limitations.count == TimingFile.limitations.count + TimingFile.ocrResolutionLimitations.count)
    }

    @Test(
      "다른 모드의 측정 파일에는 OCR 해상도 비교 키가 없다",
      arguments: [RecordingMode.accuracy, .speed(count: 100)]
    )
    func otherModesOmitComparison(mode: RecordingMode) async throws {
      let fixture = RecorderFixture(
        album: [.stub(id: "a", isScreenshot: true)],
        library: [.stub(id: "b", isScreenshot: true)]
      )

      await fixture.record(mode)

      let result = try #require(fixture.model.phase.result)
      #expect(result.ocrComparison == nil)
      let timing = try jsonObject(result.timingFile)
      #expect(timing["ocrResolution"] == nil)
      #expect((timing["limitations"] as? [String])?.count == TimingFile.limitations.count)
      let images = try #require(timing["images"] as? [[String: Any]])
      #expect(images.allSatisfy { $0["ocrComparison"] == nil })
    }
  }
#endif
