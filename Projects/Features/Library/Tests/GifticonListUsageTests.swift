import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 기프티콘 목록 줄 버튼·줄 밀기로 사용 여부 바꾸기와 다시 읽기 겹침. 쓰기를 붙잡을 때는 `onSetGifticonUsed`, 목록 읽기는 `onGifticons` 에
/// `CallGates` 를 쓴다. 실패는 `setUsedError` 를 쓴다.
@MainActor
struct GifticonListUsageTests {
  @Test("미사용 줄을 밀어 사용함으로 하면 저장소에 쓰고 목록·쓰기 번호·줄별 변경이 바뀐다. 사용함 탭에서 되돌린다")
  func swipeTogglesUsage() async {
    let photoStore = Self.photoStore()
    let model = GifticonFixture.listModel(photoStore: photoStore)
    let appear = await Self.open(model)

    await model.usageToggled(id: "g", toUsed: true)
    #expect(photoStore.usedIDs == ["g"])
    #expect(Self.isUsed(model, "g") == true)
    #expect(Self.isUsed(model, "h") == false)
    #expect(model.usageRevision == 1)
    #expect(model.usageChanges == ["g": GifticonUsageChange(id: "g", isUsed: true, sequence: 1)])
    #expect(model.updatingUsageIDs.isEmpty)
    #expect(model.alert == nil)

    await model.usageToggled(id: "g", toUsed: false)
    #expect(photoStore.usedIDs.isEmpty)
    #expect(Self.isUsed(model, "g") == false)
    #expect(model.usageRevision == 2)
    #expect(model.usageChanges == ["g": GifticonUsageChange(id: "g", isUsed: false, sequence: 2)])

    // 쓰기가 끝날 때마다 저장소 값과 맞추려 다시 읽는다.
    await waitUntil { photoStore.gifticonsCallCount >= 3 }
    #expect(Self.isUsed(model, "g") == false)

    await cancelAndWait(appear)
  }

  @Test("쓰지 못하면 알리고 목록·쓰기 번호·줄별 변경은 그대로이고 다시 읽는다")
  func swipeFailureAlertsAndReloads() async {
    let photoStore = Self.photoStore(setUsedError: .failed)
    let model = GifticonFixture.listModel(photoStore: photoStore)
    let appear = await Self.open(model)
    let before = model.content

    await model.usageToggled(id: "g", toUsed: true)

    #expect(model.alert == .usageUpdateFailed)
    #expect(model.content == before)
    #expect(model.usageRevision == 0)
    #expect(model.usageChanges.isEmpty)
    #expect(model.updatingUsageIDs.isEmpty)
    await waitUntil { photoStore.gifticonsCallCount == 2 }
    #expect(Self.isUsed(model, "g") == false)

    await cancelAndWait(appear)
  }

  @Test("그사이 기프티콘이 아니게 됐으면 쓰기 번호를 올리지 않고 다시 읽어 줄을 거둔다")
  func swipeOnNonGifticonReloads() async throws {
    let photoStore = Self.photoStore()
    let model = GifticonFixture.listModel(photoStore: photoStore)
    let appear = await Self.open(model)
    try await photoStore.save([.dated(id: "g", nil, categories: [.shopping])])

    await model.usageToggled(id: "g", toUsed: true)

    #expect(model.usageRevision == 0)
    #expect(model.usageChanges.isEmpty)
    #expect(model.alert == nil)
    await waitUntil { model.content.ids == ["h"] }

    await cancelAndWait(appear)
  }

  @Test("같은 줄을 쓰는 동안 다시 밀어도 한 번만 쓰고, 다른 줄은 함께 쓴다")
  func sameRowIgnoredWhileUpdating() async {
    let gates = CallGates(holding: [0])
    let photoStore = Self.photoStore(onSetGifticonUsed: { await gates.pass($0) })
    let model = GifticonFixture.listModel(photoStore: photoStore)
    let appear = await Self.open(model)

    let first = Task { await model.usageToggled(id: "g", toUsed: true) }
    await waitUntil { gates.hasEntered(0) }
    #expect(model.updatingUsageIDs == ["g"])

    await model.usageToggled(id: "g", toUsed: true)
    #expect(photoStore.setGifticonUsedCount == 1)

    await model.usageToggled(id: "h", toUsed: true)
    #expect(photoStore.setGifticonUsedCount == 2)
    #expect(model.updatingUsageIDs == ["g"])
    #expect(Self.isUsed(model, "h") == true)

    gates.open(0)
    await first.value
    #expect(photoStore.setGifticonUsedCount == 2)
    #expect(photoStore.usedIDs == ["g", "h"])
    #expect(model.updatingUsageIDs.isEmpty)
    #expect(model.usageRevision == 2)

    await cancelAndWait(appear)
  }

  @Test("두 줄의 쓰기가 성공하면 줄별 변경에 둘 다 남는다")
  func changesKeptPerRow() async {
    let photoStore = Self.photoStore()
    let model = GifticonFixture.listModel(photoStore: photoStore)
    let appear = await Self.open(model)

    await model.usageToggled(id: "g", toUsed: true)
    await model.usageToggled(id: "h", toUsed: true)

    #expect(model.usageChanges == [
      "g": GifticonUsageChange(id: "g", isUsed: true, sequence: 1),
      "h": GifticonUsageChange(id: "h", isUsed: true, sequence: 2),
    ])

    await cancelAndWait(appear)
  }

  @Test("이미 그 값인 줄을 밀면 쓰지 않는다")
  func swipeToSameValueIsIgnored() async {
    let photoStore = Self.photoStore(usedIDs: ["h"])
    let model = GifticonFixture.listModel(photoStore: photoStore)
    let appear = await Self.open(model)

    await model.usageToggled(id: "h", toUsed: true)
    await model.usageToggled(id: "g", toUsed: false)

    #expect(photoStore.setGifticonUsedCount == 0)
    #expect(model.usageRevision == 0)
    #expect(model.usageChanges.isEmpty)
    #expect(photoStore.usedIDs == ["h"])

    await cancelAndWait(appear)
  }

  @Test("쓰기 전에 시작한 다시 읽기는 쓴 값을 되돌리지 않고 한 번 더 읽는다")
  func reloadStartedBeforeWriteDoesNotRevert() async {
    let gates = CallGates(holding: [1, 2])
    let photoStore = Self.photoStore(onGifticons: { await gates.pass($0) })
    let model = GifticonFixture.listModel(photoStore: photoStore)
    let appear = await Self.open(model)

    // 미사용 값을 읽어 둔 채 붙잡힌 다시 읽기.
    model.libraryStoreChanged()
    await waitUntil { gates.hasEntered(1) }

    await model.usageToggled(id: "g", toUsed: true)
    #expect(Self.isUsed(model, "g") == true)

    gates.open(1)
    // 지난 값을 버리고 다시 읽는다. 그동안 쓴 값이 그대로다.
    await waitUntil { gates.hasEntered(2) }
    #expect(Self.isUsed(model, "g") == true)
    #expect(model.usageRevision == 1)

    gates.open(2)
    await waitUntil { photoStore.gifticonsCallCount >= 4 }
    #expect(Self.isUsed(model, "g") == true)

    await cancelAndWait(appear)
  }

  @Test("쓰는 중에 끝난 다시 읽기는 버리고, 쓰기가 끝난 뒤 다시 읽어 그사이 바뀐 값을 보인다")
  func reloadDuringWriteIsDeferred() async throws {
    let gates = CallGates(holding: [0])
    let photoStore = Self.photoStore(onSetGifticonUsed: { await gates.pass($0) })
    let model = GifticonFixture.listModel(photoStore: photoStore)
    let appear = await Self.open(model)

    let write = Task { await model.usageToggled(id: "g", toUsed: true) }
    await waitUntil { gates.hasEntered(0) }

    try await photoStore.save([.gifticon(id: "n", creationDate: .seoul(2026, 10, 18, hour: 12), expiryDate: nil)])
    model.libraryStoreChanged()
    await waitUntil { photoStore.gifticonsCallCount == 2 }
    #expect(model.content.ids?.contains("n") == false)

    gates.open(0)
    await write.value
    await waitUntil { model.content.ids?.contains("n") == true }
    #expect(Self.isUsed(model, "g") == true)
    #expect(model.usageRevision == 1)

    await cancelAndWait(appear)
  }

  @Test("화면을 닫은 뒤 실패하면 알리지 않고, 닫은 뒤 성공해도 쓰기 번호는 오른다")
  func writeFinishingAfterClose() async {
    // 성공.
    let gates = CallGates(holding: [0], ignoresCancellation: true)
    defer { gates.open(0) }
    let photoStore = Self.photoStore(onSetGifticonUsed: { await gates.pass($0) })
    let model = GifticonFixture.listModel(photoStore: photoStore)
    let appear = await Self.open(model)
    let write = Task { await model.usageToggled(id: "g", toUsed: true) }
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(appear)
    gates.open(0)
    await write.value

    #expect(model.usageRevision == 1)
    #expect(model.usageChanges["g"] == GifticonUsageChange(id: "g", isUsed: true, sequence: 1))
    #expect(Self.isUsed(model, "g") == true)
    #expect(model.updatingUsageIDs.isEmpty)
    #expect(model.alert == nil)

    // 실패.
    let failingGates = CallGates(holding: [0], ignoresCancellation: true)
    defer { failingGates.open(0) }
    let failingStore = Self.photoStore(setUsedError: .failed, onSetGifticonUsed: { await failingGates.pass($0) })
    let failingModel = GifticonFixture.listModel(photoStore: failingStore)
    let failingAppear = await Self.open(failingModel)
    let failingWrite = Task { await failingModel.usageToggled(id: "g", toUsed: true) }
    await waitUntil { failingGates.hasEntered(0) }
    await cancelAndWait(failingAppear)
    failingGates.open(0)
    await failingWrite.value

    #expect(failingModel.alert == nil)
    #expect(failingModel.usageRevision == 0)
    #expect(failingModel.usageChanges.isEmpty)
    #expect(failingModel.updatingUsageIDs.isEmpty)
  }

  @Test("알림을 닫으면 지운다")
  func alertDismissedClears() async {
    let photoStore = Self.photoStore(setUsedError: .failed)
    let model = GifticonFixture.listModel(photoStore: photoStore)
    let appear = await Self.open(model)
    await model.usageToggled(id: "g", toUsed: true)
    #expect(model.alert == .usageUpdateFailed)

    model.alertDismissed()
    #expect(model.alert == nil)

    await cancelAndWait(appear)
  }

  @Test("저장소가 없거나 목록을 읽기 전이면 밀어도 아무것도 하지 않는다")
  func swipeIgnoredWithoutStoreOrBeforeLoad() async {
    let missing = GifticonFixture.listModel(photoStore: nil)
    await missing.usageToggled(id: "g", toUsed: true)
    #expect(missing.usageRevision == 0)
    #expect(missing.updatingUsageIDs.isEmpty)

    let gates = CallGates(holding: [0])
    let photoStore = Self.photoStore(onGifticons: { await gates.pass($0) })
    let model = GifticonFixture.listModel(photoStore: photoStore)
    let appear = Task { await model.onAppear() }
    await waitUntil { gates.hasEntered(0) }
    #expect(model.content == .loading)

    await model.usageToggled(id: "g", toUsed: true)
    #expect(photoStore.setGifticonUsedCount == 0)
    #expect(model.updatingUsageIDs.isEmpty)
    #expect(model.usageRevision == 0)

    gates.open(0)
    await cancelAndWait(appear)
  }

  // MARK: - Helpers

  /// 미사용 기프티콘 둘(최신순 g, h).
  private static func photoStore(
    usedIDs: Set<ImageAsset.ID> = [],
    setUsedError: PhotoStoreError? = nil,
    onGifticons: @escaping @Sendable (Int) async -> Void = { _ in },
    onSetGifticonUsed: @escaping @Sendable (Int) async -> Void = { _ in }
  ) -> PhotoStoreClientFake {
    PhotoStoreClientFake(
      images: [
        .gifticon(id: "g", creationDate: .seoul(2026, 10, 2, hour: 12), expiryDate: .date(2026, 11, 1)),
        .gifticon(id: "h", creationDate: .seoul(2026, 10, 1, hour: 12), expiryDate: .date(2026, 11, 2)),
      ],
      usedIDs: usedIDs,
      onGifticons: onGifticons,
      setUsedError: setUsedError,
      onSetGifticonUsed: onSetGifticonUsed
    )
  }

  /// 화면을 열고 처음 읽기가 끝날 때까지 기다린다.
  private static func open(_ model: GifticonListModel) async -> Task<Void, Never> {
    let appear = Task { await model.onAppear() }
    await waitUntil {
      if case .loaded = model.content {
        return true
      }
      return false
    }
    return appear
  }

  private static func isUsed(_ model: GifticonListModel, _ id: ImageAsset.ID) -> Bool? {
    model.content.items?.first { $0.id == id }?.isUsed
  }
}
