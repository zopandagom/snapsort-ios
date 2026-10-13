#if DEBUG
  import Core
  import Foundation
  import ImageAnalysisTesting
  import PhotoLibraryInterface
  import PhotoLibraryTesting
  import Testing
  @testable import SampleRecorderFeature

  /// 기록 도구의 이벤트 → 상태. Fake 로 보관함과 분석을 흉내 내고, 결과 파일은 JSON 을 풀어 확인한다.
  @MainActor
  struct SampleRecorderModelTests {
    // MARK: - 정확도 모드

    @Test("정확도 모드는 앨범 순서대로 샘플을 기록하고, predicted 는 Core 기준으로 거른 라벨로 계산한 규칙 분류 결과다")
    func recordsAlbumSamplesInOrder() async throws {
      let fixture = RecorderFixture(
        album: [.stub(id: "gift", isScreenshot: true), .stub(id: "meal", coordinate: seoul)],
        labels: [
          "gift": [ImageLabel(identifier: "screenshot", confidence: 0.9)],
          "meal": [ImageLabel(identifier: "food", confidence: 0.8)],
        ],
        text: ["gift": ["선물하기", "유효기간 2026.12.31"], "meal": ["메뉴판"]]
      )

      await fixture.record(.accuracy)

      let result = try #require(fixture.model.phase.result)
      #expect(fixture.model.phase == .finished(result))
      let samples = try jsonArray(result.samplesFile)
      #expect(samples.map { $0["name"] as? String } == ["앨범 001", "앨범 002"])
      #expect(samples.map { $0["predicted"] as? [String] } == [["gifticon"], ["food"]])
      #expect(samples.map { $0["text"] as? [String] } == [["선물하기", "유효기간 2026.12.31"], ["메뉴판"]])
      #expect(result.recordedSampleCount == 2)
    }

    @Test("정확도 모드는 OCR 대상이 아닌 이미지도 원본을 읽어 OCR 한다")
    func readsTextOfNonTargetsInAccuracyMode() async {
      let fixture = RecorderFixture(
        album: [.stub(id: "meal", coordinate: seoul)],
        labels: ["meal": [ImageLabel(identifier: "food", confidence: 0.8)]]
      )

      await fixture.record(.accuracy)

      #expect(fixture.photoLibrary.loadImageRequests == [
        LoadImageRequest(id: "meal", size: .thumbnail),
        LoadImageRequest(id: "meal", size: .largestAvailable),
      ])
      #expect(fixture.imageAnalysis.requests.contains(.recognizeText))
    }

    @Test("라벨은 기록 하한(0.01)으로 받아 샘플에 남기고, 분류에는 Core 기준 이상만 쓴다")
    func recordsLowConfidenceLabelsWithoutUsingThem() async throws {
      let fixture = RecorderFixture(
        album: [.stub(id: "meal", coordinate: seoul)],
        labels: ["meal": [
          ImageLabel(identifier: "food", confidence: 0.8),
          ImageLabel(identifier: "document", confidence: 0.05),
          ImageLabel(identifier: "dog", confidence: 0.005),
        ]],
        text: ["meal": ["영수증", "합계 9,000"]]
      )

      await fixture.record(.accuracy)

      #expect(fixture.imageAnalysis.requests.first == .classify(minimumConfidence: 0.01))
      let sample = try #require(try jsonArray(fixture.model.phase.result?.samplesFile).first)
      let labels = try #require(sample["labels"] as? [[String: Any]])
      #expect(labels.map { $0["identifier"] as? String } == ["food", "document"])
      // 0.05 `document` 를 쓰면 OCR 대상이 되어 문서·영수증으로도 분류된다.
      #expect(sample["predicted"] as? [String] == ["food"])
    }

    @Test("이미지마다 썸네일 로드 → 분류 → 원본 로드 → OCR 순서로 분석한다")
    func analyzesStagesInOrder() async {
      let fixture = RecorderFixture(album: [.stub(id: "a"), .stub(id: "b", isScreenshot: true)])

      await fixture.record(.accuracy)

      #expect(fixture.log.all == [
        "load:a:thumbnail", "classify:a", "load:a:largest", "ocr:a",
        "load:b:thumbnail", "classify:b", "load:b:largest", "ocr:b",
      ])
    }

    // MARK: - 속도 모드

    @Test("속도 모드는 최신 N장만 처리하고, OCR 대상이 아니면 원본을 읽지 않으며 샘플 파일을 만들지 않는다")
    func speedModeProcessesLatestImages() async throws {
      let library = (0 ..< 5).map { ImageAsset.stub(id: "photo-\($0)", coordinate: seoul) }
      let fixture = RecorderFixture(
        library: library,
        labels: Dictionary(uniqueKeysWithValues: library.map {
          ($0.id, [ImageLabel(identifier: "food", confidence: 0.8)])
        })
      )

      await fixture.record(.speed(count: 3))

      let result = try #require(fixture.model.phase.result)
      #expect(fixture.photoLibrary.loadImageRequests == ["photo-0", "photo-1", "photo-2"].map {
        LoadImageRequest(id: $0, size: .thumbnail)
      })
      #expect(result.samplesFile == nil)
      #expect(try jsonObject(result.timingFile)["processedCount"] as? Int == 3)
    }

    @Test("속도 모드는 보관함이 N장보다 작으면 있는 만큼만 처리한다")
    func speedModeProcessesWholeSmallLibrary() async throws {
      let fixture = RecorderFixture(library: .stubs(count: 2))

      await fixture.record(.speed(count: 100))

      #expect(try jsonObject(fixture.model.phase.result?.timingFile)["processedCount"] as? Int == 2)
    }

    @Test("속도 모드 측정 파일에 보관함 수·요청 수·여행 판정 시간이 있다")
    func speedModeRecordsLibraryCountAndTravelDetection() async throws {
      let fixture = RecorderFixture(library: .stubs(count: 5))

      await fixture.record(.speed(count: 3))

      let timing = try jsonObject(fixture.model.phase.result?.timingFile)
      #expect(timing["mode"] as? String == "speed")
      #expect(timing["libraryCount"] as? Int == 5)
      #expect(timing["requestedCount"] as? Int == 3)
      #expect(timing["travelDetectionMs"] is Double)
      #expect(timing["access"] as? String == "authorized")
    }

    @Test("정확도 모드 측정 파일에는 속도 모드 값이 없다")
    func accuracyModeOmitsSpeedValues() async throws {
      let fixture = RecorderFixture(album: [.stub(id: "a")])

      await fixture.record(.accuracy)

      let timing = try jsonObject(fixture.model.phase.result?.timingFile)
      #expect(timing["mode"] as? String == "accuracy")
      #expect(timing["libraryCount"] == nil)
      #expect(timing["requestedCount"] == nil)
      #expect(timing["travelDetectionMs"] == nil)
      #expect(timing["labelRecordingFloor"] as? Double == 0.01)
      #expect(timing["labelConfidenceThreshold"] as? Double == 0.1)
    }

    // MARK: - 사전 실패

    @Test(
      "이미지를 처리하기 전에 멈추면 실패 이유를 보인다",
      arguments: [
        (
          PhotoAccessState.denied,
          RecordingMode.accuracy,
          [ImageAsset]?.some([.stub(id: "a")]),
          RecordingFailure.notAuthorized
        ),
        (.notDetermined, .speed(count: 100), nil, .notAuthorized),
        (.limited, .accuracy, [.stub(id: "a")], .limitedAccess),
        (.authorized, .accuracy, nil, .albumNotFound),
        (.authorized, .accuracy, [], .albumEmpty),
        (.authorized, .speed(count: 100), nil, .noImages),
      ]
    )
    func failsBeforeProcessing(
      access: PhotoAccessState,
      mode: RecordingMode,
      album: [ImageAsset]?,
      expected: RecordingFailure
    ) async {
      let fixture = RecorderFixture(access: access, album: album)

      await fixture.record(mode)

      #expect(fixture.model.phase == .failed(expected))
      #expect(!fixture.model.isRecording)
      #expect(fixture.photoLibrary.loadImageRequests.isEmpty)
    }

    @Test("제한 접근에서도 속도 모드는 기록하고 접근 상태를 남긴다")
    func speedModeWorksWithLimitedAccess() async throws {
      let fixture = RecorderFixture(access: .limited, library: .stubs(count: 2))

      await fixture.record(.speed(count: 100))

      #expect(try jsonObject(fixture.model.phase.result?.timingFile)["access"] as? String == "limited")
    }

    // MARK: - 건너뛰기

    @Test("읽거나 분석하지 못한 이미지는 이유와 단계를 남기고 샘플에서 빼고 나머지를 계속한다")
    func skipsFailedImages() async throws {
      let ids = ["ok", "cloud", "broken", "gone", "classify", "largest", "ocr", "last"]
      var loadErrors: [ImageAsset.ID: ImageLoadError] = ["cloud": .notAvailableLocally, "broken": .failed]
      loadErrors["gone"] = .notFound
      let fixture = RecorderFixture(
        album: ids.map { .stub(id: $0) },
        loadErrors: loadErrors,
        largestErrors: ["largest": .failed],
        classifyFailures: ["classify"],
        recognizeFailures: ["ocr"]
      )

      await fixture.record(.accuracy)

      let result = try #require(fixture.model.phase.result)
      #expect(result.skipped == [
        SkippedImage(index: 1, reason: .unavailable, stage: .thumbnailLoad),
        SkippedImage(index: 2, reason: .unavailable, stage: .thumbnailLoad),
        SkippedImage(index: 3, reason: .gone, stage: .thumbnailLoad),
        SkippedImage(index: 4, reason: .analysisFailed, stage: .classify),
        SkippedImage(index: 5, reason: .unavailable, stage: .largestLoad),
        SkippedImage(index: 6, reason: .analysisFailed, stage: .ocr),
      ])
      #expect(try jsonArray(result.samplesFile).map { $0["name"] as? String } == ["앨범 001", "앨범 008"])
      let timing = try jsonObject(result.timingFile)
      let images = try #require(timing["images"] as? [[String: Any]])
      #expect(images.map { $0["outcome"] as? String } == [
        "recorded", "skipped", "skipped", "skipped", "skipped", "skipped", "skipped", "recorded",
      ])
      #expect(images[5]["failedStage"] as? String == "largestLoad")
      #expect(images[5]["pipelineMs"] == nil)
      let skipped = try #require((timing["summary"] as? [String: Any])?["skipped"] as? [String: Int])
      #expect(skipped == ["unavailable": 3, "gone": 1, "analysisFailed": 2])
    }

    @Test("모두 건너뛰어도 끝난 것으로 보고, 샘플 파일 없이 측정 파일만 만든다")
    func finishesWhenAllSkipped() async throws {
      let fixture = RecorderFixture(album: [.stub(id: "a"), .stub(id: "b")], classifyFailures: ["a", "b"])

      await fixture.record(.accuracy)

      let result = try #require(fixture.model.phase.result)
      #expect(fixture.model.phase == .finished(result))
      #expect(result.samplesFile == nil)
      #expect(result.timingFile.file != nil)
      #expect(result.recordedSampleCount == 0)
    }

    @Test("iCloud 대체 버전으로 읽은 이미지를 센다")
    func countsLocalFallbacks() async throws {
      let fixture = RecorderFixture(album: [.stub(id: "local"), .stub(id: "cloud")], fallbackIDs: ["cloud"])

      await fixture.record(.accuracy)

      let result = try #require(fixture.model.phase.result)
      #expect(result.fallbackCount == 1)
      let images = try #require(try jsonObject(result.timingFile)["images"] as? [[String: Any]])
      #expect(images.map { $0["thumbnailFallback"] as? Bool } == [false, true])
      #expect(images.map { $0["ocrFallback"] as? Bool } == [false, true])
    }
  }
#endif
