#if DEBUG
  import Core
  import Foundation
  import ImageAnalysisTesting
  import PhotoLibraryInterface
  import PhotoLibraryTesting
  import Testing
  @testable import SampleRecorderFeature

  /// 번호로 기록 모드: 샘플 보기와 같은 번호 목록의 지금 보관함 사진을 입력 순서로, OCR 대상과 관계없이 모두 OCR 해 기록한다.
  /// 입력 실패·범위 밖 번호·권한 실패는 이미지를 처리하기 전에 멈추고, 멈춤·샘플 보기와의 관계는 다른 모드와 같다.
  @MainActor
  struct SampleRecorderModelNumberedTests {
    @Test("번호로 기록 모드는 입력 순서대로 지금 보관함의 그 번째 이미지를 기록하고, 샘플 이름에 번호를 남긴다")
    func recordsNumberedImagesInInputOrder() async throws {
      let fixture = RecorderFixture(library: .stubs(count: 5))

      await fixture.record(numbers: "3, 1")

      let result = try #require(fixture.model.phase.result)
      #expect(fixture.model.phase == .finished(result))
      #expect(try jsonArray(result.samplesFile).map { $0["name"] as? String } == ["보관함 00003", "보관함 00001"])
      #expect(fixture.log.all == [
        "load:image-2:thumbnail", "classify:image-2", "barcode:image-2", "load:image-2:largest", "ocr:image-2",
        "load:image-0:thumbnail", "classify:image-0", "barcode:image-0", "load:image-0:largest", "ocr:image-0",
      ])
      #expect(try jsonObject(result.timingFile)["processedCount"] as? Int == 2)
      #expect(result.recordedSampleCount == 2)
    }

    @Test("번호로 기록 모드는 OCR 대상이 아닌 이미지도 원본을 읽어 OCR 하고 ocrSkipped 를 쓰지 않는다")
    func readsTextOfNonTargets() async throws {
      let meal = ImageAsset.stub(id: "meal", coordinate: seoul)
      let labels = [ImageLabel(identifier: "food", confidence: 0.8)]
      let text = ["선물하기", "유효기간 2026.12.31"]
      // OCR 줄을 쓰면 분류가 달라지는 입력이라야 predicted 가 OCR 줄 없이 계산됐는지 가릴 수 있다.
      #expect(!TextRecognitionPolicy.needsTextRecognition(asset: meal, labels: labels))
      #expect(
        RuleClassifier.classify(asset: meal, labels: labels, textLines: text.map(RecorderFixture.line))
          != RuleClassifier.classify(asset: meal, labels: labels, textLines: [])
      )
      let fixture = RecorderFixture(library: [meal], labels: ["meal": labels], text: ["meal": text])

      await fixture.record(numbers: "1")

      #expect(fixture.photoLibrary.loadImageRequests == [
        LoadImageRequest(id: "meal", size: .thumbnail),
        LoadImageRequest(id: "meal", size: .largestAvailable),
      ])
      #expect(fixture.imageAnalysis.requests.contains(.recognizeText))
      let sample = try #require(try jsonArray(fixture.model.phase.result?.samplesFile).first)
      #expect(sample["text"] as? [String] == text)
      #expect(sample["ocrSkipped"] == nil)
      #expect(sample["predicted"] as? [String] == ["food"])
    }

    @Test("원본 로드나 OCR 에 실패한 번호는 OCR 대상이 아니어도 건너뛰고, 처리 순서와 단계를 남기고 나머지를 계속한다")
    func skipsFailedNumbers() async throws {
      let fixture = RecorderFixture(
        library: [.stub(id: "a"), .stub(id: "b"), .stub(id: "c"), .stub(id: "d")],
        largestErrors: ["b": .notAvailableLocally],
        recognizeFailures: ["c"]
      )

      await fixture.record(numbers: "4, 2, 3, 1")

      let result = try #require(fixture.model.phase.result)
      #expect(fixture.model.phase == .finished(result))
      #expect(result.skipped == [
        SkippedImage(index: 1, reason: .unavailable, stage: .largestLoad),
        SkippedImage(index: 2, reason: .analysisFailed, stage: .ocr),
      ])
      #expect(try jsonArray(result.samplesFile).map { $0["name"] as? String } == ["보관함 00004", "보관함 00001"])
      let images = try #require(try jsonObject(result.timingFile)["images"] as? [[String: Any]])
      #expect(images.map { $0["index"] as? Int } == [0, 1, 2, 3])
      #expect(images.map { $0["outcome"] as? String } == ["recorded", "skipped", "skipped", "recorded"])
    }

    @Test(
      "번호 입력이 잘못되면 기록을 시작하지 않고 실패를 보이며 권한 확인·보관함 조회를 하지 않는다",
      arguments: [
        ("1, abc", SampleNumberFailure.invalidTokens(["abc"])),
        (" , ", .noNumbers),
        ((1 ... 101).map(String.init).joined(separator: " "), .tooMany(count: 101)),
      ]
    )
    func rejectsInvalidNumbers(input: String, failure: SampleNumberFailure) async throws {
      let fetches = ValueSequence([0])
      let conditions = ValueSequence([normalConditions])
      let fixture = RecorderFixture(
        library: [.stub(id: "a")],
        fetchGate: { _ = fetches.next() },
        deviceConditions: { conditions.next() }
      )
      // 앞 기록이 끝난 결과와 보던 샘플 목록이 있는 상태에서 시작한다.
      await fixture.record(numbers: "1")
      _ = try #require(fixture.model.phase.result)
      await fixture.model.sampleShowTapped()
      _ = try #require(fixture.model.samplePreview.list)
      let fetchCount = fetches.readCount
      let conditionsReadCount = conditions.readCount
      let requestCount = fixture.photoLibrary.loadImageRequests.count

      fixture.model.sampleNumberInputChanged(input)
      await fixture.model.startTapped()

      #expect(fixture.model.phase == .failed(.invalidNumbers(failure)))
      #expect(!fixture.model.isRecording)
      #expect(fetches.readCount == fetchCount)
      #expect(conditions.readCount == conditionsReadCount)
      #expect(fixture.photoLibrary.loadImageRequests.count == requestCount)
      #expect(try #require(fixture.model.samplePreview.list).rows.map(\.number) == [1])
    }

    @Test("보관함 장수보다 큰 번호가 있으면 이미지를 처리하기 전에 범위 밖 번호와 장수로 실패하고, 빈 보관함이면 이미지가 없다고 실패한다")
    func failsOutOfRangeNumbers() async {
      let fixture = RecorderFixture(library: .stubs(count: 3))

      await fixture.record(numbers: "2, 5, 9")

      #expect(fixture.model.phase == .failed(.numbersOutOfRange([5, 9], libraryCount: 3)))
      #expect(fixture.photoLibrary.loadImageRequests.isEmpty)

      let empty = RecorderFixture()

      await empty.record(numbers: "1")

      #expect(empty.model.phase == .failed(.noImages))
    }

    @Test(
      "번호로 기록은 전체 접근에서만 되고, 권한이 없으면 기기 상태도 읽지 않는다",
      arguments: [
        (PhotoAccessState.limited, RecordingFailure.limitedAccess),
        (.denied, .notAuthorized),
      ]
    )
    func requiresFullAccess(access: PhotoAccessState, expected: RecordingFailure) async {
      let conditions = ValueSequence([normalConditions])
      let fixture = RecorderFixture(
        access: access,
        library: [.stub(id: "a")],
        deviceConditions: { conditions.next() }
      )

      await fixture.record(numbers: "1")

      #expect(fixture.model.phase == .failed(expected))
      #expect(conditions.readCount == 0)
      #expect(fixture.photoLibrary.loadImageRequests.isEmpty)
    }

    @Test("측정 파일에 mode·보관함 수가 있고 요청 수·여행 판정 시간은 없으며, 파일 이름에 모드 태그가 있다")
    func timingFileHasModeAndLibraryCount() async throws {
      let fixture = RecorderFixture(
        library: [.stub(id: "secret-a"), .stub(id: "secret-b"), .stub(id: "secret-c")],
        text: ["secret-c": ["비밀 메모"]]
      )

      await fixture.record(numbers: "3")

      let timingFile = try #require(fixture.model.phase.result?.timingFile.file)
      #expect(timingFile.fileName == "IndexingTiming-numberedAccuracy-20270115-1700.json")
      let timing = try jsonObject(fixture.model.phase.result?.timingFile)
      #expect(timing["mode"] as? String == "numberedAccuracy")
      #expect(timing["libraryCount"] as? Int == 3)
      #expect(timing["requestedCount"] == nil)
      #expect(timing["travelDetectionMs"] == nil)
      let raw = try #require(String(data: timingFile.data, encoding: .utf8))
      #expect(!raw.contains("secret"))
      #expect(!raw.contains("비밀 메모"))
      #expect(!raw.contains("보관함"))
    }

    @Test("기록 도중 멈추면 끝난 번호만 부분 결과로 남는다")
    func cancelsDuringRecording() async throws {
      let started = Flag()
      let fixture = RecorderFixture(
        library: .stubs(count: 3),
        classifyGate: { id in
          if id == "image-0" {
            await waitUntilCancelled(started)
          }
        }
      )
      fixture.model.sampleNumberInputChanged("3, 1, 2")
      fixture.model.modeChanged(.numberedAccuracy)
      let start = Task { await fixture.model.startTapped() }
      await waitUntil { started.isSet }

      fixture.model.cancelTapped()
      await start.value

      #expect(fixture.model.phase.cancelReason == .user)
      let result = try #require(fixture.model.phase.result)
      #expect(try jsonArray(result.samplesFile).map { $0["name"] as? String } == ["보관함 00003"])
      #expect(!fixture.photoLibrary.loadImageRequests.contains { $0.id == "image-1" })
    }

    @Test("번호로 기록을 시작하면 보던 샘플 목록을 닫고 번호 입력은 그대로 둔다")
    func startClosesPreviewAndKeepsInput() async throws {
      let fixture = RecorderFixture(library: [.stub(id: "a"), .stub(id: "b")])
      fixture.model.sampleNumberInputChanged("2")
      await fixture.model.sampleShowTapped()
      _ = try #require(fixture.model.samplePreview.list)

      await fixture.record(.numberedAccuracy)

      #expect(fixture.model.samplePreview.isIdle)
      #expect(fixture.model.sampleNumberInput == "2")
      let result = try #require(fixture.model.phase.result)
      #expect(try jsonArray(result.samplesFile).map { $0["name"] as? String } == ["보관함 00002"])
    }

    @Test("기록을 시작한 뒤 번호 입력이 바뀌어도 시작할 때 해석한 번호로 기록한다")
    func usesNumbersParsedAtStart() async throws {
      let gate = FirstCallGate()
      let fixture = RecorderFixture(library: .stubs(count: 4), loadGate: { _ in await gate.wait() })
      fixture.model.sampleNumberInputChanged("2")
      fixture.model.modeChanged(.numberedAccuracy)
      let start = Task { await fixture.model.startTapped() }
      await waitUntil { gate.started.isSet }

      fixture.model.sampleNumberInputChanged("4")
      gate.release.set()
      await start.value

      let result = try #require(fixture.model.phase.result)
      #expect(fixture.model.phase == .finished(result))
      #expect(try jsonArray(result.samplesFile).map { $0["name"] as? String } == ["보관함 00002"])
      #expect(!fixture.photoLibrary.loadImageRequests.contains { $0.id == "image-3" })
    }
  }
#endif
