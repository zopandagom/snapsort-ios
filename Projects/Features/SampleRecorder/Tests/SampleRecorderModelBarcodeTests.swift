#if DEBUG
  import Core
  import Foundation
  import ImageAnalysisTesting
  import PhotoLibraryTesting
  import Testing
  @testable import SampleRecorderFeature

  /// 기록 도구가 운영 1단계처럼 위치 없고 라벨로는 OCR 대상이 아닌 이미지의 바코드를 확인해 OCR 대상 판정에 쓰고 시간을 재는지
  /// (docs/ARCHITECTURE.md §4 기록 도구). 바코드 내용은 남기지 않는다.
  @MainActor
  struct SampleRecorderModelBarcodeTests {
    static let date = Date(timeIntervalSince1970: 1_790_000_000)
    static let foodLabels = [ImageLabel(identifier: "food", confidence: 0.8)]
    static let couponText = ["교환처 카페", "유효기간 2026.12.31"]

    @Test("바코드를 찾으면 OCR 대상으로 보고 벡터 없이 원본을 OCR 하며, 초안에 hasBarcode 를 남긴다")
    func barcodeMakesTextTarget() async throws {
      let fixture = RecorderFixture(
        library: [.stub(id: "coupon", creationDate: Self.date)],
        labels: ["coupon": Self.foodLabels],
        text: ["coupon": Self.couponText],
        isFeaturePrintAvailable: true,
        barcodeIDs: ["coupon"]
      )

      await fixture.record(.libraryAccuracy)

      #expect(fixture.log.all == [
        "load:coupon:thumbnail",
        "classify:coupon",
        "barcode:coupon",
        "load:coupon:largest",
        "ocr:coupon",
      ])
      let result = try #require(fixture.model.phase.result)
      let image = try #require(try (jsonObject(result.timingFile)["images"] as? [[String: Any]])?.first)
      #expect(image["needsTextRecognition"] as? Bool == true)
      #expect(image["barcodeMs"] is Double)
      #expect(image["hasBarcode"] as? Bool == true)
      let sample = try #require(try jsonArray(result.samplesFile).first)
      #expect(sample["ocrSkipped"] == nil)
      #expect((sample["asset"] as? [String: Any])?["hasBarcode"] as? Bool == true)
      #expect((sample["predicted"] as? [String])?.contains("gifticon") == true)
    }

    @Test("바코드가 없으면 초안에 hasBarcode 키가 없고 벡터 대상이면 벡터를 만든다")
    func noBarcodeKeepsNonTarget() async throws {
      let fixture = RecorderFixture(
        library: [.stub(id: "meal", creationDate: Self.date)],
        labels: ["meal": Self.foodLabels],
        text: ["meal": Self.couponText],
        isFeaturePrintAvailable: true
      )

      await fixture.record(.libraryAccuracy)

      #expect(fixture.log.all == ["load:meal:thumbnail", "classify:meal", "barcode:meal", "featurePrint:meal"])
      let result = try #require(fixture.model.phase.result)
      let image = try #require(try (jsonObject(result.timingFile)["images"] as? [[String: Any]])?.first)
      #expect(image["needsTextRecognition"] as? Bool == false)
      #expect(image["hasBarcode"] as? Bool == false)
      let sample = try #require(try jsonArray(result.samplesFile).first)
      #expect((sample["asset"] as? [String: Any])?.keys.contains("hasBarcode") == false)
      #expect(sample["ocrSkipped"] as? Bool == true)
    }

    @Test("위치 있는 사진과 이미 OCR 대상인 이미지는 바코드를 확인하지 않는다")
    func skipsNonCheckTargets() async throws {
      let fixture = RecorderFixture(
        album: [
          .stub(id: "located", creationDate: Self.date, coordinate: seoul),
          .stub(id: "shot", creationDate: Self.date, isScreenshot: true),
          .stub(id: "text", creationDate: Self.date),
        ],
        labels: [
          "located": Self.foodLabels,
          "shot": Self.foodLabels,
          "text": [ImageLabel(identifier: "document", confidence: 0.9)],
        ],
        barcodeIDs: ["located", "shot", "text"]
      )

      await fixture.record(.accuracy)

      #expect(!fixture.log.all.contains { $0.hasPrefix("barcode:") })
      #expect(!fixture.imageAnalysis.requests.contains(.detectBarcodes))
      let images = try #require(try jsonObject(fixture.model.phase.result?.timingFile)["images"] as? [[String: Any]])
      #expect(images.allSatisfy { $0["barcodeMs"] == nil && $0["hasBarcode"] == nil })
    }

    @Test("바코드 인식이 실패해도 이미지를 건너뛰지 않고 바코드 없음으로 판정하며 시간을 비운다")
    func keepsImageWhenBarcodeFails() async throws {
      let fixture = RecorderFixture(
        library: [.stub(id: "meal", creationDate: Self.date)],
        labels: ["meal": Self.foodLabels],
        barcodeFailures: ["meal"]
      )

      await fixture.record(.libraryAccuracy)

      let result = try #require(fixture.model.phase.result)
      #expect(result.skipped.isEmpty)
      #expect(result.recordedSampleCount == 1)
      let image = try #require(try (jsonObject(result.timingFile)["images"] as? [[String: Any]])?.first)
      #expect(image["outcome"] as? String == "recorded")
      #expect(image["needsTextRecognition"] as? Bool == false)
      #expect(image["barcodeMs"] == nil)
      #expect(image["hasBarcode"] == nil)
      #expect(image["pipelineMs"] is Double)
    }

    @Test("바코드 인식 도중 멈추면 그 이미지는 남기지 않는다")
    func cancelsDuringBarcodeCheck() async throws {
      let started = Flag()
      let fixture = RecorderFixture(
        album: [.stub(id: "a"), .stub(id: "b"), .stub(id: "c")],
        barcodeGate: { id in
          if id == "b" {
            await waitUntilCancelled(started)
          }
        }
      )
      fixture.model.modeChanged(.accuracy)
      let start = Task { await fixture.model.startTapped() }
      await waitUntil { started.isSet }

      fixture.model.cancelTapped()
      await start.value

      #expect(fixture.model.phase.cancelReason == .user)
      let result = try #require(fixture.model.phase.result)
      #expect(try jsonArray(result.samplesFile).map { $0["name"] as? String } == ["앨범 001"])
      #expect(try jsonObject(result.timingFile)["processedCount"] as? Int == 1)
      #expect(!fixture.photoLibrary.loadImageRequests.contains { $0.id == "c" })
    }

    @Test("운영 시간(pipelineMs)에 잰 바코드 확인 시간을 1단계로 더한다")
    func pipelineIncludesBarcode() {
      var measurement = ImageMeasurement(index: 0, asset: .stub(id: "coupon", creationDate: Self.date))
      measurement.thumbnailLoadMs = 1
      measurement.classifyMs = 2
      measurement.barcodeMs = 4
      #expect(SampleRecording.pipelineMs(of: measurement, needsText: false) == 7)
      measurement.featurePrintMs = 8
      #expect(SampleRecording.pipelineMs(of: measurement, needsText: false) == 15)
      measurement.largestLoadMs = 16
      measurement.ocrMs = 32
      #expect(SampleRecording.pipelineMs(of: measurement, needsText: true) == 63)
    }

    @Test("측정 파일과 샘플 초안에 바코드 내용이 나오지 않는다")
    func omitsBarcodePayload() async throws {
      let fixture = RecorderFixture(
        library: [.stub(id: "coupon", creationDate: Self.date)],
        labels: ["coupon": Self.foodLabels],
        text: ["coupon": Self.couponText],
        barcodeIDs: ["coupon"]
      )

      await fixture.record(.libraryAccuracy)

      let result = try #require(fixture.model.phase.result)
      let timing = try #require(result.timingFile.file)
      let samples = try #require(result.samplesFile?.file)
      let timingText = String(bytes: timing.data, encoding: .utf8) ?? ""
      let samplesText = String(bytes: samples.data, encoding: .utf8) ?? ""
      #expect(timingText.contains("hasBarcode"))
      #expect(!timingText.contains(fixtureBarcodePayload))
      #expect(!samplesText.contains(fixtureBarcodePayload))
    }
  }
#endif
