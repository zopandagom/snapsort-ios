import ClassifierTesting
import Core
import Foundation
import ImageAnalysisTesting
import IndexingInterface
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import IndexingImpl

/// 분석 두 단계: 1단계(분류 저장)와 2단계(OCR 대기 이미지의 글자 읽기), 2단계 도중의 변경·멈춤·실패.
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplTwoPassTests {
  @Test("새 이미지를 모두 분류해 저장한 뒤에 OCR 대상만 원본을 읽는다")
  func classifiesAllBeforeRecognizing() async {
    let fixture = Fixture(
      library: [
        .stub(id: "shot-1", isScreenshot: true),
        .stub(id: "meal", coordinate: seoul),
        .stub(id: "shot-2", isScreenshot: true),
      ],
      labels: ["meal": [ImageLabel(identifier: "food", confidence: 0.8)]]
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }

    let requests = fixture.photoLibrary.loadImageRequests
    let lastThumbnail = requests.lastIndex { $0.size == .thumbnail }
    let firstLargest = requests.firstIndex { $0.size == .largestAvailable }
    #expect(requests.count { $0.size == .thumbnail } == 3)
    #expect(lastThumbnail.flatMap { last in firstLargest.map { last < $0 } } == true)
    #expect(Set(fixture.photoLibrary.largestLoadIDs) == ["shot-1", "shot-2"])
  }

  @Test("1단계는 대상 아님을 규칙 분류로, OCR 대상을 대기와 라벨만의 카테고리(기타 제외)로 저장하고, 2단계가 글자로 카테고리를 더한다")
  func storesPendingThenRecognized() async throws {
    let gift = ImageAsset.stub(id: "gift", isScreenshot: true)
    let note = ImageAsset.stub(id: "note", isScreenshot: true)
    let blank = ImageAsset.stub(id: "blank", isScreenshot: true)
    let meal = ImageAsset.stub(id: "meal", coordinate: seoul)
    let fixture = Fixture(
      library: [gift, note, blank, meal],
      labels: [
        "note": [ImageLabel(identifier: "receipt", confidence: 0.8)],
        "meal": [ImageLabel(identifier: "food", confidence: 0.8)],
      ],
      text: ["gift": ["교환처 GS25", "유효기간 2026.12.31"]]
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }

    let first = try #require(fixture.store.savedBatches.first)
    let classified = Dictionary(uniqueKeysWithValues: first.map { ($0.id, $0) })
    #expect(classified["meal"]?.textRecognition == .notNeeded)
    #expect(classified["meal"]?.categories == [.food])
    #expect(classified["gift"]?.textRecognition == .pending)
    #expect(classified["gift"]?.categories == [])
    #expect(classified["note"]?.categories == [.receipt])
    #expect(classified["blank"]?.categories == [])

    let stored = Dictionary(uniqueKeysWithValues: fixture.store.images.map { ($0.id, $0) })
    #expect(stored["gift"]?.textLines?.map(\.text) == ["교환처 GS25", "유효기간 2026.12.31"])
    #expect(stored["gift"]?.categories == [.gifticon])
    #expect(stored["note"]?.categories == [.receipt])
    // 글자를 읽어도 아무것도 못 찾은 이미지만 기타다.
    #expect(stored["blank"]?.textRecognition == .recognized([]))
    #expect(stored["blank"]?.categories == [.other])
  }

  @Test("2단계는 최신순(날짜 없음은 맨 뒤)으로 정한 장 수마다 읽어 저장한다")
  func recognizesNewestFirstInBatches() async {
    let fixture = Fixture(
      library: [
        .stub(id: "day-1", creationDate: date(month: 5, day: 1), isScreenshot: true),
        .stub(id: "undated", isScreenshot: true),
        .stub(id: "day-3", creationDate: date(month: 5, day: 3), isScreenshot: true),
        .stub(id: "day-2", creationDate: date(month: 5, day: 2), isScreenshot: true),
      ],
      textBatchSize: 2
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    let finished = await progress.next { $0.isFinished }

    #expect(fixture.photoLibrary.largestLoadIDs == ["day-3", "day-2", "day-1", "undated"])
    #expect(fixture.store.savedBatches.dropFirst().map { $0.map(\.id) } == [["day-3", "day-2"], ["day-1", "undated"]])
    #expect(finished == IndexingProgress(totalCount: 4, indexedCount: 4, skippedCount: 0, recognizedTextCount: 4))
  }

  @Test("저장소에 대기 이미지가 있으면 다시 분류하지 않고 첫 진행률부터 대기 수를 보이며 2단계만 한다")
  func resumesPendingWithoutReclassifying() async throws {
    let receipt = ImageAsset.stub(id: "receipt", isScreenshot: true)
    let labels = [ImageLabel(identifier: "receipt", confidence: 0.8)]
    let gate = Gate()
    let fixture = Fixture(
      library: [receipt],
      stored: [pending(receipt, labels: labels)],
      text: ["receipt": ["합계 9,000"]],
      onRecognize: { _ in await gate.wait() }
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    // OCR 을 붙잡아 두었으므로 첫 진행률은 비교를 마친 직후의 값이다.
    let first = try #require(await progress.next())
    gate.open()
    let finished = await progress.next { $0.isFinished }

    #expect(first == IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0, pendingTextCount: 1))
    #expect(first.phase == .recognizingText)
    #expect(finished == IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0, recognizedTextCount: 1))
    #expect(fixture.photoLibrary.loadImageRequests == [LoadImageRequest(id: "receipt", size: .largestAvailable)])
    // 라벨은 저장된 것을 쓴다.
    #expect(fixture.store.images.first?.labels == labels)
    #expect(fixture.store.images.first?.categories == [.receipt])
  }

  @Test("2단계에서 원본을 읽거나 OCR 하지 못하면 대기로 남기고 미룬 수로 세며, 같은 실행에서는 다시 하지 않고 전체 다시 비교에서 다시 한다")
  func retriesTextFailuresOnReloadAll() async {
    let library: [ImageAsset] = [
      .stub(id: "ocr-fail", isScreenshot: true),
      .stub(id: "icloud", isScreenshot: true),
      .stub(id: "ok", isScreenshot: true),
    ]
    let fixture = Fixture(
      library: library,
      largestErrors: ["icloud": .notAvailableLocally],
      recognizeFailures: ["ocr-fail"]
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    let first = await progress.next { $0.isFinished }
    #expect(first == IndexingProgress(
      totalCount: 3,
      indexedCount: 3,
      skippedCount: 0,
      recognizedTextCount: 1,
      skippedTextCount: 2
    ))
    #expect(fixture.store.images.filter { $0.textRecognition == .pending }.map(\.id) == ["icloud", "ocr-fail"])
    #expect(fixture.photoLibrary.largestLoadIDs.count == 3)

    fixture.recognizeFailures.removeAll()
    fixture.photoLibrary.sendReloadAll(imageAssets: library)
    let retried = await progress.next { $0.isFinished && $0.recognizedTextCount == 2 }

    #expect(retried == IndexingProgress(
      totalCount: 3,
      indexedCount: 3,
      skippedCount: 0,
      recognizedTextCount: 2,
      skippedTextCount: 1
    ))
    #expect(fixture.photoLibrary.largestLoadIDs.count { $0 == "ocr-fail" } == 2)
  }

  @Test("2단계에서 보관함에 없다고 나오면 저장 결과는 지우지 않고 전체 수·대기 수에서 뺀다")
  func keepsStoredResultWhenGoneInTextPass() async {
    let fixture = Fixture(
      library: [.stub(id: "gone", isScreenshot: true), .stub(id: "ok", isScreenshot: true)],
      largestErrors: ["gone": .notFound]
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    let finished = await progress.next { $0.isFinished }

    #expect(finished == IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0, recognizedTextCount: 1))
    #expect(fixture.store.images.map(\.id) == ["gone", "ok"])
    #expect(fixture.store.deletedBatches.isEmpty)
  }

  @Test("저장 수는 보관함에 있는 것만 세어, 사라진 이미지의 삭제보다 새 사진 추가가 먼저 와도 새 사진을 분류하기 전에는 1단계다")
  func countsOnlyLibraryImagesAsIndexed() {
    var run = IndexingRun(
      photoLibrary: PhotoLibraryClientFake(),
      imageAnalysis: ImageAnalysisClientFake(),
      photoStore: PhotoStoreClientFake(),
      classifier: ClassifierClientFake(isModelAvailable: false),
      calendar: Calendar(identifier: .gregorian),
      batchSize: 50,
      textBatchSize: 10
    )
    // 2단계에서 `notFound` 로 보관함에서 뺐지만 저장 결과는 남은 "gone", 그 뒤에 추가된 "new".
    run.assets = ["ok": .stub(id: "ok"), "new": .stub(id: "new")]
    run.indexedIDs = ["gone", "ok"]

    #expect(run.progress == IndexingProgress(totalCount: 2, indexedCount: 1, skippedCount: 0))
    #expect(run.progress.phase == .classifying)
  }
}
