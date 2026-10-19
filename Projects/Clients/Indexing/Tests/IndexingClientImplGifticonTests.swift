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
/// 소급은 진행률을 보내지 않으므로 `isFinished` 를 기다리지 않고, 변경 스트림을 끝낸 뒤 `run()` 스트림이 끝날 때까지 읽는다
/// (루프는 소급·2단계를 다 마쳐야 돌아온다).
@Suite(.timeLimit(.minutes(1)))
struct IndexingClientImplGifticonTests {
  /// 만료일(연도 생략)과 교환처가 있는 기프티콘 줄. 키워드 두 개로 기프티콘이 된다.
  static let gifticonText = ["교환처 카페", "유효기간 12월 31일"]
  static let extracted = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: "카페")

  @Test("2단계에서 기프티콘으로 분류되면 생성일과 주입한 달력으로 추출해 함께 저장한다")
  func extractsGifticonInTextPass() async {
    let fixture = Fixture(
      library: [.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)],
      text: ["coupon": Self.gifticonText]
    )

    await Self.runToEnd(fixture)

    let image = fixture.store.images.only
    #expect(image?.categories == [.gifticon])
    #expect(image?.gifticon == Self.extracted)
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

    await Self.runToEnd(fixture)

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
      text: ["coupon": Self.gifticonText]
    )

    await Self.runToEnd(fixture)

    #expect(fixture.store.images.only?.gifticon == GifticonInfo(expiryDate: nil, redemptionPlace: "카페"))
  }

  @Test("추출하지 않은 저장 행은 OCR 없이 저장된 줄로 소급 추출하고, 진행률은 소급 대상이 없을 때와 같다")
  func backfillsStoredGifticonWithoutRecognizing() async {
    let asset = ImageAsset.stub(id: "coupon", creationDate: date(month: 10, day: 1), isScreenshot: true)
    let fixture = Fixture(library: [asset], stored: [recognizedGifticon(asset, text: Self.gifticonText)])
    let extractedFixture = Fixture(
      library: [asset],
      stored: [recognizedGifticon(asset, text: Self.gifticonText, gifticon: Self.extracted)]
    )

    let last = await Self.runToEnd(fixture)
    let lastWithoutTargets = await Self.runToEnd(extractedFixture)

    #expect(fixture.store.savedGifticonBatches == [["coupon": Self.extracted]])
    #expect(fixture.store.images.only?.gifticon == Self.extracted)
    #expect(fixture.photoLibrary.loadImageRequests.isEmpty)
    #expect(fixture.analysis.requests.isEmpty)
    #expect(extractedFixture.store.savedGifticonBatches.isEmpty)
    #expect(last == lastWithoutTargets)
    #expect(last?.isFinished == true)
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
      stored: assets.map { recognizedGifticon($0, text: Self.gifticonText) },
      batchSize: 2
    )

    await Self.runToEnd(fixture)

    #expect(fixture.store.savedGifticonBatches.map { Set($0.keys) } == [
      ["day-5", "day-4"], ["day-3", "day-2"], ["day-1"],
    ])
    #expect(fixture.store.images.allSatisfy { $0.gifticon == Self.extracted })
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
      stored: assets.map { recognizedGifticon($0, text: Self.gifticonText) },
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

  @Test("추출 값을 저장하지 못하면 멈추고, 다음 실행은 저장하지 못한 이미지만 소급 추출한다")
  func resumesBackfillAfterStoreFailure() async {
    let assets = ["a", "b"].enumerated().map { index, id in
      ImageAsset.stub(id: id, creationDate: date(month: 5, day: 2 - index), isScreenshot: true)
    }
    let fixture = Fixture(
      library: assets,
      stored: assets.map { recognizedGifticon($0, text: Self.gifticonText) },
      gifticonSaveLimit: 1,
      batchSize: 1
    )

    // 변경 스트림을 끝내지 않아도 저장소 실패로 스트림이 끝난다.
    for await _ in fixture.indexing.run() {}

    #expect(fixture.store.savedGifticonBatches.map { Set($0.keys) } == [["a"]])
    #expect(Self.storedGifticons(fixture) == ["a": Self.extracted])

    // 한도가 남은 같은 저장소는 다시 실패하므로, 저장 결과를 넘겨 새로 만든다.
    let next = Fixture(library: assets, stored: fixture.store.images, batchSize: 1)
    await Self.runToEnd(next)

    #expect(next.store.savedGifticonBatches.map { Set($0.keys) } == [["b"]])
    #expect(next.store.images.allSatisfy { $0.gifticon == Self.extracted })
  }

  @Test("보관함에 없는 소급 대상은 행을 지우고 추출하지 않는다")
  func skipsBackfillOutsideLibrary() async {
    let gone = ImageAsset.stub(id: "gone", creationDate: date(month: 5, day: 1), isScreenshot: true)
    let fixture = Fixture(
      library: [.stub(id: "photo", coordinate: seoul)],
      stored: [indexed("photo"), recognizedGifticon(gone, text: Self.gifticonText)]
    )

    await Self.runToEnd(fixture)

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
      stored: assets.map { recognizedGifticon($0, text: Self.gifticonText) },
      missingOnIDRead: ["a"]
    )

    await Self.runToEnd(fixture)

    #expect(fixture.store.savedGifticonBatches == [["b": Self.extracted]])
    #expect(Self.storedGifticons(fixture) == ["b": Self.extracted])
  }

  /// 저장소에서 추출 값이 있는 이미지만.
  static func storedGifticons(_ fixture: Fixture) -> [ImageAsset.ID: GifticonInfo] {
    fixture.store.images.reduce(into: [:]) { result, image in
      result[image.id] = image.gifticon
    }
  }

  /// 변경 스트림을 끝내고 `run()` 스트림이 끝날 때까지 읽어 마지막 진행률을 돌려준다.
  @discardableResult
  static func runToEnd(_ fixture: Fixture) async -> IndexingProgress? {
    fixture.photoLibrary.finishImageChanges()
    var last: IndexingProgress?
    for await progress in fixture.indexing.run() {
      last = progress
    }
    return last
  }
}
