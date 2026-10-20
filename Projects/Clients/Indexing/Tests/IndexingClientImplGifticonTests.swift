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

/// 기프티콘 추출: 2단계에서 함께 저장하고, 추출하지 않은 저장 행은 OCR 없이 저장된 줄로 소급 추출한다.
/// 소급은 진행률·`isFinished` 에 넣지 않으므로 `isFinished` 를 기다리지 않고, 변경 스트림을 끝낸 뒤 `run()` 스트림이 끝날 때까지 읽는다
/// (루프는 소급·2단계를 다 마쳐야 돌아온다).
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplGifticonTests {
  @Test("2단계에서 기프티콘으로 분류되면 생성일과 주입한 달력으로 추출해 함께 저장한다")
  func extractsGifticonInTextPass() async {
    let fixture = Fixture(
      library: [.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)],
      text: ["coupon": gifticonText]
    )

    await fixture.runToEnd()

    let image = fixture.store.images.only
    #expect(image?.categories == [.gifticon])
    #expect(image?.gifticon == extractedGifticon)
    #expect(fixture.store.savedGifticonBatches.isEmpty)
  }

  @Test("2단계: 기프티콘이 아니면 추출 값이 없고, 기프티콘인데 아무것도 못 찾으면 두 값이 모두 비어 있다")
  func storesNoGifticonOrEmptyGifticon() async {
    let fixture = Fixture(
      library: [
        .stub(id: "receipt", creationDate: date(month: 10, day: 2), isScreenshot: true),
        .stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true),
      ],
      text: [
        "receipt": ["영수증", "합계 12,000원"],
        "coupon": ["선물하기", "모바일쿠폰"],
      ]
    )

    await fixture.runToEnd()

    let images = Dictionary(uniqueKeysWithValues: fixture.store.images.map { ($0.id, $0) })
    #expect(images["receipt"]?.categories == [.receipt])
    #expect(images["receipt"]?.gifticon == nil)
    #expect(images["coupon"]?.categories == [.gifticon])
    #expect(images["coupon"]?.gifticon == GifticonInfo(expiryDate: nil, redemptionPlace: nil))
  }

  @Test("생성일이 없으면 연도를 생략한 만료일은 비우고 교환처는 저장한다")
  func leavesYearlessExpiryEmptyWithoutCreationDate() async {
    let fixture = Fixture(
      library: [.stub(id: "coupon", isScreenshot: true)],
      text: ["coupon": gifticonText]
    )

    await fixture.runToEnd()

    #expect(fixture.store.images.only?.gifticon == GifticonInfo(expiryDate: nil, redemptionPlace: "카페"))
  }

  @Test("추출하지 않은 저장 행은 OCR 없이 저장된 줄로 소급 추출하고, 진행률은 소급 대상이 없을 때와 같다")
  func backfillsStoredGifticonWithoutRecognizing() async {
    let asset = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(library: [asset], stored: [recognizedGifticon(asset, text: gifticonText)])
    let extractedFixture = Fixture(
      library: [asset],
      stored: [recognizedGifticon(asset, text: gifticonText, gifticon: extractedGifticon)]
    )

    let last = await fixture.runToEnd()
    let lastWithoutTargets = await extractedFixture.runToEnd()

    #expect(fixture.store.savedGifticonBatches == [["coupon": extractedGifticon]])
    #expect(fixture.store.images.only?.gifticon == extractedGifticon)
    #expect(fixture.photoLibrary.loadImageRequests.isEmpty)
    #expect(fixture.analysis.requests.isEmpty)
    #expect(extractedFixture.store.savedGifticonBatches.isEmpty)
    #expect(last == lastWithoutTargets)
    #expect(last?.isFinished == true)
  }

  @Test(
    "소급 대상이 비면 직전과 같은 값의 진행률을 한 번 더 보낸다. 배치가 여럿이어도 한 번이다",
    arguments: [IndexingClientImpl.defaultBatchSize, 2]
  )
  func reportsOnceWhenBackfillEnds(batchSize: Int) async {
    let assets = (1 ... 5).map { ImageAsset.stub(
      id: "day-\($0)",
      creationDate: date(month: 5, day: $0),
      isScreenshot: true
    ) }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedGifticon($0, text: gifticonText) },
      batchSize: batchSize
    )
    let extractedFixture = Fixture(
      library: assets,
      stored: assets.map { recognizedGifticon($0, text: gifticonText, gifticon: extractedGifticon) },
      batchSize: batchSize
    )

    let progresses = await fixture.allProgress()
    let progressesWithoutTargets = await extractedFixture.allProgress()

    #expect(fixture.store.images.allSatisfy { $0.gifticon == extractedGifticon })
    #expect(Array(progresses.dropLast()) == progressesWithoutTargets)
    #expect(progresses.last == progressesWithoutTargets.last)
  }

  @Test("소급 추출은 최신순으로 batchSize 장씩 나눠 저장한다")
  func backfillsInBatches() async {
    let assets = (1 ... 5).map { ImageAsset.stub(
      id: "day-\($0)",
      creationDate: date(month: 5, day: $0),
      isScreenshot: true
    ) }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedGifticon($0, text: gifticonText) },
      batchSize: 2
    )

    await fixture.runToEnd()

    #expect(fixture.store.savedGifticonBatches.map { Set($0.keys) } == [
      ["day-5", "day-4"], ["day-3", "day-2"], ["day-1"],
    ])
    #expect(fixture.store.images.allSatisfy { $0.gifticon == extractedGifticon })
  }

  @Test("소급 배치 사이에 온 삭제 변경을 먼저 반영하고, 지워진 이미지는 추출 값을 저장하지 않는다")
  func appliesRemovalBetweenBackfillBatches() async {
    let library = Later<PhotoLibraryClientFake>()
    let changeRequests = ChangeRequests()
    let assets = ["a", "b", "c"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 3 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedGifticon($0, text: gifticonText) },
      onSaveGifticons: { gifticons in
        if Set(gifticons.keys) == ["a"] {
          library.current?.sendIncrementalChange(removed: ["b"])
          // 처음 요청 1번 + 이 변경을 받아 수신함에 넣은 뒤의 요청 1번. 그 뒤에 저장을 끝내 다음 배치 경계에서 반영되게 한다.
          await changeRequests.wait(until: 2)
          library.current?.finishImageChanges()
        }
      },
      batchSize: 1,
      changeRequests: changeRequests
    )
    library.set(fixture.photoLibrary)

    for await _ in fixture.indexing.run() {}

    #expect(fixture.store.savedGifticonBatches.map { Set($0.keys) } == [["a"], ["c"]])
    #expect(fixture.store.deletedBatches == [["b"]])
    #expect(fixture.store.images.map(\.id) == ["a", "c"])
  }

  @Test("보관함에 없는 소급 대상은 행을 지우고 추출하지 않는다")
  func skipsBackfillOutsideLibrary() async {
    let gone = ImageAsset.stub(id: "gone", creationDate: date(month: 5, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [.stub(id: "photo", coordinate: seoul)],
      stored: [indexed("photo"), recognizedGifticon(gone, text: gifticonText)]
    )

    await fixture.runToEnd()

    #expect(fixture.store.deletedBatches == [["gone"]])
    #expect(fixture.store.savedGifticonBatches.isEmpty)
    #expect(fixture.store.images.map(\.id) == ["photo"])
  }

  @Test("소급 대상의 저장 행을 읽지 못하면 그 이미지만 건너뛰고 끝난다")
  func skipsBackfillTargetMissingOnRead() async {
    let assets = ["a", "b"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 2 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedGifticon($0, text: gifticonText) },
      missingOnIDRead: ["a"]
    )

    await fixture.runToEnd()

    #expect(fixture.store.savedGifticonBatches == [["b": extractedGifticon]])
    #expect(fixture.storedGifticons == ["b": extractedGifticon])
  }
}

// 기프티콘 테스트(IndexingClientImplGifticonTests·IndexingClientImplGifticonFailureTests) 공통 준비.

/// 만료일(연도 생략)과 교환처가 있는 기프티콘 줄. 키워드 두 개로 기프티콘이 된다.
let gifticonText = ["교환처 카페", "유효기간 12월 31일"]
/// `gifticonText` 를 2026년 생성일로 추출한 값.
let extractedGifticon = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: "카페")
/// 기프티콘이 아닌 OCR 줄(영수증).
let receiptText = ["영수증", "합계 12,000원"]
/// OCR 대상이 아닌 사진의 라벨. 위치와 함께 두면 1단계에서 끝난다.
let photoLabels = [ImageLabel(identifier: "food", confidence: 0.8)]

/// 2단계를 마친 기프티콘 저장 결과. `gifticon` 이 nil 이면 추출하지 않은 행(소급 추출 대상)이다.
/// 보강 상태를 주지 않으면 규칙 추출만 한 값을 저장할 때와 같게 둔다(두 값이 있으면 마침, 아니면 보강 대기).
func recognizedGifticon(
  _ asset: ImageAsset,
  text: [String],
  gifticon: GifticonInfo? = nil,
  modelFill: GifticonModelFill? = nil
) -> IndexedImage {
  IndexedImage(
    asset: asset,
    labels: defaultLabels,
    textRecognition: .recognized(ocrLines(text)),
    categories: [.gifticon],
    gifticon: gifticon,
    gifticonModelFill: modelFill ?? .initial(for: gifticon)
  )
}

extension Fixture {
  /// 저장소에서 추출 값이 있는 이미지만.
  var storedGifticons: [ImageAsset.ID: GifticonInfo] {
    self.store.images.reduce(into: [:]) { result, image in
      result[image.id] = image.gifticon
    }
  }

  /// 변경 스트림을 끝내고 인덱싱을 끝까지 돌려 보낸 진행률을 모두 돌려준다. `run()` 스트림은 늦게 읽으면 지난 값을 버리므로
  /// 진행률 수를 세는 테스트는 이것을 쓴다.
  func allProgress() async -> [IndexingProgress] {
    self.photoLibrary.finishImageChanges()
    var run = self.indexing.makeRun()
    var progresses: [IndexingProgress] = []
    await run.start { progresses.append($0) }
    return progresses
  }

  /// 변경 스트림을 끝내고 `run()` 스트림이 끝날 때까지 읽어 마지막 진행률을 돌려준다.
  @discardableResult
  func runToEnd() async -> IndexingProgress? {
    self.photoLibrary.finishImageChanges()
    var last: IndexingProgress?
    for await progress in self.indexing.run() {
      last = progress
    }
    return last
  }
}
