import Core
import Foundation
import MapTesting
import PasteboardTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 상세의 사용함 전환·기프티콘 다시 읽기. 쓰기를 붙잡을 때는 `onSetGifticonUsed`, 한 장 읽기는 `onGifticon` 에 `CallGates` 를 쓴다.
@MainActor
struct CaptureActionsUsageTests {
  @Test("사용함으로 표시하면 저장소에 쓰고 사용 여부와 쓰기 번호가 바뀐다. 다시 누르면 되돌린다")
  func usedButtonTogglesUsage() async {
    let photoStore = Self.photoStore()
    let model = GifticonFixture.captureModel(photoStore: photoStore)
    let detail = await Self.open(model, photoStore: photoStore)

    await model.usedButtonTapped()
    #expect(model.gifticon?.isUsed == true)
    #expect(model.usageRevision == 1)
    #expect(!model.isUpdatingUsage)
    #expect(photoStore.usedIDs == ["g"])

    await model.usedButtonTapped()
    #expect(model.gifticon?.isUsed == false)
    #expect(model.usageRevision == 2)
    #expect(photoStore.usedIDs.isEmpty)

    await cancelAndWait(detail)
  }

  @Test("쓰지 못하면 알리고 사용 여부와 쓰기 번호는 그대로다")
  func usedButtonFailureAlerts() async {
    let photoStore = PhotoStoreClientFake(
      images: [.gifticon(id: "g", expiryDate: .date(2026, 11, 1))],
      setUsedError: .failed
    )
    let model = GifticonFixture.captureModel(photoStore: photoStore)
    let detail = await Self.open(model, photoStore: photoStore)

    await model.usedButtonTapped()

    #expect(model.alert == .usageUpdateFailed)
    #expect(model.gifticon?.isUsed == false)
    #expect(model.usageRevision == 0)
    #expect(!model.isUpdatingUsage)

    model.alertDismissed()
    #expect(model.alert == nil)

    await cancelAndWait(detail)
  }

  @Test("그사이 기프티콘이 아니게 됐으면 쓰지 않고 다시 읽어 기프티콘 영역을 거둔다")
  func usedButtonOnNonGifticonReloads() async throws {
    let photoStore = Self.photoStore()
    let model = GifticonFixture.captureModel(photoStore: photoStore)
    let detail = await Self.open(model, photoStore: photoStore)
    try await photoStore.save([.dated(id: "g", nil, categories: [.shopping])])

    await model.usedButtonTapped()

    await waitUntil { model.gifticon == nil }
    #expect(model.usageRevision == 0)
    #expect(model.barcode == .notApplicable)

    await cancelAndWait(detail)
  }

  @Test("쓰는 동안 다시 눌러도 한 번만 쓴다")
  func usedButtonIgnoredWhileUpdating() async {
    let gates = CallGates(holding: [0])
    let photoStore = PhotoStoreClientFake(
      images: [.gifticon(id: "g", expiryDate: .date(2026, 11, 1))],
      onSetGifticonUsed: { await gates.pass($0) }
    )
    let model = GifticonFixture.captureModel(photoStore: photoStore)
    let detail = await Self.open(model, photoStore: photoStore)

    let first = Task { await model.usedButtonTapped() }
    await waitUntil { gates.hasEntered(0) }
    #expect(model.isUpdatingUsage)
    await model.usedButtonTapped()

    gates.open(0)
    await first.value
    #expect(photoStore.setGifticonUsedCount == 1)
    #expect(model.gifticon?.isUsed == true)

    await cancelAndWait(detail)
  }

  @Test("상세를 닫은 뒤 끝난 쓰기도 쓰기 번호를 올리고, 새로 연 상세의 상태는 바꾸지 않는다")
  func writeFinishingAfterCloseStillSignals() async {
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = PhotoStoreClientFake(
      images: [
        .gifticon(id: "g", expiryDate: .date(2026, 11, 1)),
        .gifticon(id: "h", expiryDate: .date(2026, 11, 2)),
      ],
      onSetGifticonUsed: { await gates.pass($0) }
    )
    let model = GifticonFixture.captureModel(photoStore: photoStore)
    let first = await Self.open(model, photoStore: photoStore)
    let write = Task { await model.usedButtonTapped() }
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(first)

    let second = Task { await model.detailAppeared(id: "h", gifticon: CaptureActionsModelTests.item("h")) }
    await waitUntil { model.detailID == "h" && model.captureInfo != .loading }
    gates.open(0)
    await write.value

    #expect(model.usageRevision == 1)
    #expect(photoStore.usedIDs == ["g"])
    #expect(model.gifticon?.id == "h")
    #expect(model.gifticon?.isUsed == false)
    #expect(!model.isUpdatingUsage)

    await cancelAndWait(second)
  }

  @Test("저장소 변경 신호로 기프티콘을 다시 읽어 값이 바뀌고, 기프티콘에서 빠지면 기프티콘 영역이 사라진다")
  func storeChangeReloadsGifticon() async throws {
    let photoStore = Self.photoStore()
    let model = GifticonFixture.captureModel(photoStore: photoStore)
    let detail = await Self.open(model, photoStore: photoStore)

    try await photoStore.save([.gifticon(id: "g", expiryDate: .date(2026, 12, 24), place: "빵집")])
    model.libraryStoreChanged()
    await waitUntil {
      if case let .extracted(info) = model.gifticon?.status {
        return info.expiryDate == .date(2026, 12, 24) && info.redemptionPlace == "빵집"
      }
      return false
    }

    try await photoStore.save([.dated(id: "g", nil, categories: [.shopping])])
    model.libraryStoreChanged()
    await waitUntil { model.gifticon == nil }
    #expect(model.barcode == .notApplicable)

    await cancelAndWait(detail)
  }

  @Test("쓰기 전에 시작한 다시 읽기는 쓴 값을 되돌리지 않고 한 번 더 읽는다")
  func readOverlappingWriteIsDropped() async {
    // 0 번 읽기는 상세를 여는 쪽(`open`)이 목록 항목을 만드는 읽기다.
    let gates = CallGates(holding: [1])
    let photoStore = PhotoStoreClientFake(
      images: [.gifticon(id: "g", expiryDate: .date(2026, 11, 1))],
      onGifticon: { await gates.pass($0) }
    )
    let model = GifticonFixture.captureModel(photoStore: photoStore)
    let detail = await Self.open(model, photoStore: photoStore)

    // 미사용을 읽은 채 붙잡힌다.
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(1) }
    await model.usedButtonTapped()
    #expect(model.gifticon?.isUsed == true)

    gates.open(1)
    await waitUntil { gates.hasEntered(2) }
    await settle()
    #expect(model.gifticon?.isUsed == true)

    await cancelAndWait(detail)
  }

  @Test("쓰는 중에 끝난 다시 읽기를 버린 뒤 쓰기가 기프티콘 아님(false)으로 끝나면 스스로 다시 읽어 기프티콘 영역을 거둔다")
  func readDroppedDuringWriteThenFalseReloads() async throws {
    // 0 번 읽기는 상세를 여는 쪽(`open`)이 목록 항목을 만드는 읽기다.
    let readGates = CallGates(holding: [1])
    let writeGates = CallGates(holding: [0])
    let photoStore = PhotoStoreClientFake(
      images: [.gifticon(id: "g", expiryDate: .date(2026, 11, 1))],
      onGifticon: { await readGates.pass($0) },
      onSetGifticonUsed: { await writeGates.pass($0) }
    )
    let model = GifticonFixture.captureModel(photoStore: photoStore)
    let detail = await Self.open(model, photoStore: photoStore)

    // 다시 읽기가 기프티콘 값을 읽은 채 붙잡히고, 쓰기가 시작돼 붙잡힌다.
    model.libraryStoreChanged()
    await waitUntil { readGates.hasEntered(1) }
    let write = Task { await model.usedButtonTapped() }
    await waitUntil { writeGates.hasEntered(0) }
    // 쓰는 중에 읽기가 끝나 버려진다.
    readGates.open(1)
    await settle()
    #expect(model.gifticon != nil)
    #expect(!readGates.hasEntered(2))

    // 그사이 기프티콘이 아니게 돼 쓰기가 false 로 끝난다.
    try await photoStore.save([.dated(id: "g", nil, categories: [.shopping])])
    writeGates.open(0)
    await write.value

    await waitUntil { model.gifticon == nil }
    #expect(readGates.hasEntered(2))
    #expect(model.usageRevision == 0)
    #expect(model.barcode == .notApplicable)

    await cancelAndWait(detail)
  }

  @Test("쓰는 중에 끝난 다시 읽기를 버린 뒤 쓰기가 실패하면 스스로 다시 읽어 그사이 바뀐 값을 보인다")
  func readDroppedDuringWriteThenFailureReloads() async throws {
    let readGates = CallGates(holding: [1])
    let writeGates = CallGates(holding: [0])
    let photoStore = PhotoStoreClientFake(
      images: [.gifticon(id: "g", expiryDate: .date(2026, 11, 1))],
      onGifticon: { await readGates.pass($0) },
      setUsedError: .failed,
      onSetGifticonUsed: { await writeGates.pass($0) }
    )
    let model = GifticonFixture.captureModel(photoStore: photoStore)
    let detail = await Self.open(model, photoStore: photoStore)

    // 인덱서가 교환처를 채운 뒤의 다시 읽기가 붙잡히고, 쓰기가 시작돼 붙잡힌다.
    try await photoStore.save([.gifticon(id: "g", expiryDate: .date(2026, 11, 1), place: "빵집")])
    model.libraryStoreChanged()
    await waitUntil { readGates.hasEntered(1) }
    let write = Task { await model.usedButtonTapped() }
    await waitUntil { writeGates.hasEntered(0) }
    // 쓰는 중에 읽기가 끝나 버려진다.
    readGates.open(1)
    await settle()
    #expect(Self.place(of: model) == nil)

    writeGates.open(0)
    await write.value

    await waitUntil { Self.place(of: model) == "빵집" }
    #expect(model.alert == .usageUpdateFailed)
    #expect(model.gifticon?.isUsed == false)
    #expect(model.usageRevision == 0)

    await cancelAndWait(detail)
  }

  @Test("기프티콘 목록에서 연 상세가 아니면 다시 읽지 않고 사용함 버튼도 반응하지 않는다")
  func nonGifticonDetailIgnoresUsage() async {
    let photoStore = PhotoStoreClientFake(images: [.gifticon(id: "g", expiryDate: nil)])
    let model = GifticonFixture.captureModel(photoStore: photoStore)
    let detail = Task { await model.detailAppeared(id: "g", gifticon: nil) }
    await waitUntil { model.captureInfo != .loading }

    model.libraryStoreChanged()
    await model.usedButtonTapped()
    await settle()

    #expect(model.gifticon == nil)
    #expect(photoStore.setGifticonUsedCount == 0)

    await cancelAndWait(detail)
  }

  // MARK: - Helpers

  static func place(of model: CaptureActionsModel) -> String? {
    guard case let .extracted(info) = model.gifticon?.status else { return nil }
    return info.redemptionPlace
  }

  static func photoStore() -> PhotoStoreClientFake {
    PhotoStoreClientFake(images: [.gifticon(id: "g", expiryDate: .date(2026, 11, 1))])
  }

  /// 기프티콘 목록에서 "g" 를 연 것처럼 저장소에서 읽은 항목으로 상세를 연다.
  static func open(_ model: CaptureActionsModel, photoStore: PhotoStoreClientFake) async -> Task<Void, Never> {
    let item = try? await photoStore.gifticon(id: "g")
    let detail = Task { await model.detailAppeared(id: "g", gifticon: item) }
    await waitUntil { model.detailID == "g" && model.captureInfo != .loading }
    return detail
  }
}
