import Core
import Foundation
import IndexingInterface
import PhotoLibraryInterface
import PhotoLibraryTesting
import PhotoStoreInterface
import Testing
@testable import IndexingImpl

@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplTests {
  @Test("새 이미지를 분류하고 OCR 대상은 글자까지 읽어 라벨·OCR 줄·카테고리와 함께 저장하고 진행률을 마친다")
  func indexesNewImages() async throws {
    let food = ImageAsset.stub(id: "food", coordinate: seoul)
    let gifticon = ImageAsset.stub(id: "gifticon", isScreenshot: true)
    let fixture = Fixture(
      library: [food, gifticon],
      labels: ["food": [ImageLabel(identifier: "food", confidence: 0.8)]],
      text: ["gifticon": ["교환처 GS25", "유효기간 2026.12.31", "주문번호 1234"]]
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    let finished = await progress.next { $0.isFinished }

    #expect(finished == IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0, recognizedTextCount: 1))
    let stored = Dictionary(uniqueKeysWithValues: fixture.store.images.map { ($0.id, $0) })
    let storedFood = try #require(stored["food"])
    #expect(storedFood.labels.map(\.identifier) == ["food"])
    #expect(storedFood.textRecognition == .notNeeded)
    #expect(storedFood.categories == [.food])
    let storedGifticon = try #require(stored["gifticon"])
    let lines = try #require(storedGifticon.textLines)
    #expect(lines.map(\.text) == ["교환처 GS25", "유효기간 2026.12.31", "주문번호 1234"])
    #expect(storedGifticon.categories == RuleClassifier.classify(
      asset: gifticon,
      labels: defaultLabels,
      textLines: lines
    ))
  }

  @Test("OCR 대상만 가장 큰 버전을 읽어 OCR 한다")
  func recognizesTextOnlyForTargets() async {
    let fixture = Fixture(
      library: [.stub(id: "photo", coordinate: seoul), .stub(id: "screenshot", isScreenshot: true)],
      labels: ["photo": [ImageLabel(identifier: "food", confidence: 0.8)]]
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }

    #expect(fixture.photoLibrary.loadImageRequests == [
      LoadImageRequest(id: "photo", size: .thumbnail),
      LoadImageRequest(id: "screenshot", size: .thumbnail),
      LoadImageRequest(id: "screenshot", size: .largestAvailable),
    ])
  }

  @Test("이미 저장한 이미지는 다시 분석하지 않고, 보관함에 없는 저장 결과는 지운다")
  func analyzesOnlyDifference() async {
    let fixture = Fixture(
      library: [.stub(id: "new"), .stub(id: "kept")],
      stored: [indexed("kept"), indexed("removed")]
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    let finished = await progress.next { $0.isFinished }

    // 라벨을 정하지 않은 이미지는 기본 라벨(`defaultLabels`)이라 OCR 대상이다.
    #expect(finished == IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0, recognizedTextCount: 1))
    #expect(Set(fixture.photoLibrary.loadImageRequests.map(\.id)) == ["new"])
    #expect(fixture.store.deletedBatches == [["removed"]])
    #expect(fixture.store.images.map(\.id) == ["kept", "new"])
  }

  @Test("조회 결과에 같은 식별자가 여러 번 있어도 한 번만 분석한다")
  func analyzesDuplicateIDOnce() async {
    let fixture = Fixture(library: [.stub(id: "a"), .stub(id: "a"), .stub(id: "b")])

    var progress = fixture.indexing.run().makeAsyncIterator()
    let finished = await progress.next { $0.isFinished }

    #expect(finished == IndexingProgress(totalCount: 2, indexedCount: 2, skippedCount: 0, recognizedTextCount: 2))
    #expect(fixture.photoLibrary.loadImageRequests.count { $0.id == "a" && $0.size == .thumbnail } == 1)
  }

  @Test("1단계(분류)와 2단계(OCR)를 각각 정한 장 수마다 나눠 저장한다")
  func savesInBatches() async {
    let fixture = Fixture(library: .stubs(count: 5), batchSize: 2, textBatchSize: 3)

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }

    #expect(fixture.store.savedBatches.map(\.count) == [2, 2, 1, 3, 2])
  }

  @Test("지울 결과도 정한 장 수마다 나눠 지운다")
  func deletesInBatches() async {
    let fixture = Fixture(library: [], stored: (0 ..< 5).map { indexed("removed-\($0)") }, batchSize: 2)

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }

    #expect(fixture.store.deletedBatches.map(\.count) == [2, 2, 1])
    #expect(fixture.store.images.isEmpty)
  }

  @Test("분석 도중 구독을 끝내면 저장하지 않은 결과를 버리고 멈춘다")
  func discardsUnsavedResultsWhenCancelled() async {
    let consumer = ConsumerTask()
    let fixture = Fixture(
      library: (0 ..< 3).map { .stub(id: "image-\($0)", coordinate: seoul) },
      onClassify: { id in
        // 두 번째 이미지를 분석할 때 구독을 끝낸다. 기본 배치(50장)라 아직 아무것도 저장하지 않았다.
        if id == "image-1" {
          consumer.cancel()
        }
      }
    )

    consumer.start {
      for await _ in fixture.indexing.run() {}
    }
    await consumer.wait()
    while fixture.photoLibrary.imageChangesSubscriberCount > 0 {
      await Task.yield()
    }

    #expect(fixture.store.savedBatches.isEmpty)
    #expect(!fixture.photoLibrary.loadImageRequests.contains { $0.id == "image-2" })
  }

  @Test("읽거나 분석하지 못한 이미지는 저장하지 않고 미룬 수로 센다")
  func skipsUnavailableImages() async {
    let fixture = Fixture(
      library: [.stub(id: "icloud"), .stub(id: "broken"), .stub(id: "ok")],
      loadErrors: ["icloud": .notAvailableLocally],
      classifyFailures: ["broken"]
    )

    var progress = fixture.indexing.run().makeAsyncIterator()
    let finished = await progress.next { $0.isFinished }

    #expect(finished == IndexingProgress(totalCount: 3, indexedCount: 1, skippedCount: 2, recognizedTextCount: 1))
    #expect(fixture.store.images.map(\.id) == ["ok"])
  }

  @Test("OCR 대상인데 OCR 하지 못한 이미지는 1단계 결과(대기)로 남기고 2단계 미룬 수로 센다")
  func keepsPendingWhenTextRecognitionFails() async {
    let fixture = Fixture(library: [.stub(id: "screenshot", isScreenshot: true)], recognizeFailures: ["screenshot"])

    var progress = fixture.indexing.run().makeAsyncIterator()
    let finished = await progress.next { $0.isFinished }

    #expect(finished == IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0, skippedTextCount: 1))
    #expect(fixture.store.images.map(\.textRecognition) == [.pending])
  }

  @Test("보관함에서 사라진 이미지는 전체 수에서 뺀다")
  func dropsImagesNotFound() async {
    let fixture = Fixture(library: [.stub(id: "gone"), .stub(id: "ok")], loadErrors: ["gone": .notFound])

    var progress = fixture.indexing.run().makeAsyncIterator()
    let finished = await progress.next { $0.isFinished }

    #expect(finished == IndexingProgress(totalCount: 1, indexedCount: 1, skippedCount: 0, recognizedTextCount: 1))
  }

  @Test("보관함 사진의 위치·날짜로 여행을 판정해 저장한다")
  func replacesTrips() async throws {
    let home = (1 ... 3).map { day in
      ImageAsset.stub(id: "home-\(day)", creationDate: date(month: 4, day: day), coordinate: seoul)
    }
    let busan = (0 ..< 5).map { index in
      ImageAsset.stub(
        id: "busan-\(index)",
        creationDate: date(month: 5, day: 2).addingTimeInterval(Double(index) * 60),
        coordinate: Coordinate(latitude: 35.1796, longitude: 129.0756)
      )
    }
    let fixture = Fixture(library: home + busan)

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }

    let trip = try #require(try await fixture.store.trips().only)
    #expect(trip.assetIDs == busan.map(\.id))
  }

  @Test("분석 중 보관함에서 사라진 사진은 여행에서도 뺀다")
  func removesGoneImagesFromTrips() async throws {
    let home = (1 ... 3).map { day in
      ImageAsset.stub(id: "home-\(day)", creationDate: date(month: 4, day: day), coordinate: seoul)
    }
    let busan = (0 ..< 6).map { index in
      ImageAsset.stub(
        id: "busan-\(index)",
        creationDate: date(month: 5, day: 2).addingTimeInterval(Double(index) * 60),
        coordinate: Coordinate(latitude: 35.1796, longitude: 129.0756)
      )
    }
    let fixture = Fixture(library: home + busan, loadErrors: ["busan-5": .notFound])

    var progress = fixture.indexing.run().makeAsyncIterator()
    _ = await progress.next { $0.isFinished }

    let trip = try #require(try await fixture.store.trips().only)
    #expect(trip.assetIDs == busan.prefix(5).map(\.id))
  }

  @Test("사진을 읽을 권한이 없으면 저장 결과를 지우지 않고 끝낸다")
  func keepsStoreWithoutReadAccess() async {
    let fixture = Fixture(library: [], stored: [indexed("a")], accessState: .denied)

    var received: [IndexingProgress] = []
    for await progress in fixture.indexing.run() {
      received.append(progress)
    }

    #expect(received.isEmpty)
    #expect(fixture.store.deletedBatches.isEmpty)
    #expect(fixture.store.images.map(\.id) == ["a"])
  }

  @Test("분석 도중 저장하지 못하면 멈추고 스트림을 끝낸다")
  func finishesWhenSaveFailsDuringAnalysis() async {
    let fixture = Fixture(library: .stubs(count: 5), saveLimit: 1, batchSize: 2)

    var received: [IndexingProgress] = []
    for await progress in fixture.indexing.run() {
      received.append(progress)
    }

    #expect(fixture.store.savedBatches.map(\.count) == [2])
    #expect(received.last == IndexingProgress(totalCount: 5, indexedCount: 2, skippedCount: 0, pendingTextCount: 2))
  }

  @Test("저장소를 읽지 못하면 멈추고 스트림을 끝낸다")
  func finishesWhenStoreFails() async {
    let fixture = Fixture(library: [.stub(id: "a")], storeError: .failed)

    var received: [IndexingProgress] = []
    for await progress in fixture.indexing.run() {
      received.append(progress)
    }

    #expect(received.isEmpty)
    #expect(fixture.photoLibrary.loadImageRequests.isEmpty)
  }

  @Test("구독을 끝내면 보관함 변경 관찰도 멈춘다")
  func stopsWhenSubscriptionEnds() async {
    let fixture = Fixture(library: [.stub(id: "a")])

    do {
      var progress = fixture.indexing.run().makeAsyncIterator()
      _ = await progress.next { $0.isFinished }
      #expect(fixture.photoLibrary.imageChangesSubscriberCount == 1)
    }

    while fixture.photoLibrary.imageChangesSubscriberCount > 0 {
      await Task.yield()
    }
  }
}
