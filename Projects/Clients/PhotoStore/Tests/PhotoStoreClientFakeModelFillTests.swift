import Core
import PhotoStoreInterface
import PhotoStoreTesting
import Testing

struct PhotoStoreClientFakeModelFillTests {
  @Test("Impl 처럼 보강 대기 행만 돌려주고 보강 결과는 그 행에만 쓰며 요청을 기록한다")
  func savesModelFillsOnlyForPendingRowsLikeImpl() async throws {
    let partial = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: nil)
    let rules = GifticonInfo(expiryDate: nil, redemptionPlace: nil)
    let filled = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: "CU")
    let gifticon = { (id: String, info: GifticonInfo, fill: GifticonModelFill) in
      IndexedImage.stub(
        id: id,
        textRecognition: .recognized([]),
        categories: [.gifticon],
        gifticon: info,
        gifticonModelFill: fill
      )
    }
    let others: [IndexedImage] = [
      gifticon("done", partial, .done),
      .stub(id: "notExtracted", textRecognition: .recognized([]), categories: [.gifticon]),
      .stub(id: "ocrPending", textRecognition: .pending, categories: [.gifticon]),
    ]
    let fake = PhotoStoreClientFake(images: [
      gifticon("toFill", partial, .pending(failures: 0)),
      gifticon("toFail", partial, .pending(failures: 1)),
      gifticon("staleToFail", partial, .stale),
      gifticon("staleToDefer", partial, .stale),
      gifticon("toDefer", partial, .pending(failures: 2)),
    ] + others)
    #expect(try await fake.gifticonModelFillPendingIDs()
      == ["toFill", "toFail", "staleToFail", "staleToDefer", "toDefer"])

    var request: [ImageAsset.ID: GifticonModelFillResult] = [
      "toFill": .filled(filled),
      "toFail": .failed(rules: rules),
      "staleToFail": .failed(rules: rules),
      "staleToDefer": .deferred(rules: rules),
      "toDefer": .deferred(rules: rules),
      "missing": .filled(filled),
    ]
    for image in others {
      request[image.id] = .filled(filled)
    }
    try await fake.saveGifticonModelFills(request)

    // 다른 보강 버전(.stale)의 실패 수는 0 에서 센다.
    #expect(fake.images == ([
      gifticon("toFill", filled, .done),
      gifticon("toFail", rules, .pending(failures: 2)),
      gifticon("staleToFail", rules, .pending(failures: 1)),
      gifticon("staleToDefer", rules, .pending(failures: 0)),
      gifticon("toDefer", rules, .pending(failures: 2)),
    ] + others).sorted { $0.id < $1.id })
    #expect(fake.savedModelFillBatches == [request])
    #expect(try await fake.gifticonModelFillPendingIDs() == ["toFail", "staleToFail", "staleToDefer", "toDefer"])
  }

  @Test("Impl 처럼 실패는 한도에서 마친 것으로 두고, 규칙으로 다시 추출하면 보강 대기로 돌아간다")
  func countsFailuresAndResetsOnExtractionLikeImpl() async throws {
    let rules = GifticonInfo(expiryDate: nil, redemptionPlace: "CU")
    let complete = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: "CU")
    let fake = PhotoStoreClientFake(images: [
      .stub(
        id: "a",
        textRecognition: .recognized([]),
        categories: [.gifticon],
        gifticon: rules,
        gifticonModelFill: .pending(failures: GifticonModelFill.maximumFailures - 1)
      ),
      .stub(id: "partial", textRecognition: .recognized([]), categories: [.gifticon]),
      .stub(id: "complete", textRecognition: .recognized([]), categories: [.gifticon]),
    ])

    try await fake.saveGifticonModelFills(["a": .failed(rules: rules)])
    try await fake.saveGifticons(["partial": rules, "complete": complete])

    let read = Dictionary(uniqueKeysWithValues: fake.images.map { ($0.id, $0.gifticonModelFill) })
    #expect(read == ["a": .done, "partial": .pending(failures: 0), "complete": .done])
    #expect(try await fake.gifticonModelFillPendingIDs() == ["partial"])
  }

  @Test("소급 보강 실패를 정하면 보강 대기 조회·보강 결과 저장만 실패하고 다른 호출과 저장 결과는 그대로다")
  func failsOnlyModelFillCallsWithModelFillError() async throws {
    let pending = IndexedImage.stub(
      id: "a",
      textRecognition: .recognized([]),
      categories: [.gifticon],
      gifticon: GifticonInfo(expiryDate: nil, redemptionPlace: nil)
    )
    let fake = PhotoStoreClientFake(images: [pending], modelFillError: .failed)

    await #expect(throws: PhotoStoreError.failed) {
      try await fake.gifticonModelFillPendingIDs()
    }
    await #expect(throws: PhotoStoreError.failed) {
      try await fake.saveGifticonModelFills(["a": .filled(GifticonInfo(expiryDate: nil, redemptionPlace: "CU"))])
    }
    try await fake.save([.stub(id: "b")])

    #expect(fake.savedModelFillBatches.isEmpty)
    #expect(try await fake.images(ids: ["a"]) == [pending])
    #expect(try await fake.gifticonExtractionPendingIDs().isEmpty)
    #expect(try await fake.indexedIDs() == ["a", "b"])
  }
}
