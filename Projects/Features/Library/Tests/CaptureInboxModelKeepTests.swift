import Core
import Foundation
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 최근 스크린샷 화면의 보관 저장이 늦게 끝날 때: 저장 중 다시 누름, 결과(성공·실패)가 다음 방문 뒤 도착.
@MainActor
struct CaptureInboxModelKeepTests {
  @Test("보관을 저장하는 중에 다시 누르면 무시해, 저장은 한 번이고 끝난 뒤 다음 장으로 넘어간다")
  func keepWhileKeepingIsIgnored() async {
    let gates = CallGates(holding: [0])
    let photoStore = CleanupFixture.store(onKeepInCaptureInbox: { await gates.pass($0) })
    let model = CleanupFixture.inboxModel(photoStore: photoStore)
    let appear = await model.open()

    let keep = Task { await model.keepTapped() }
    await waitUntil { gates.hasEntered(0) }
    #expect(model.keepingID == "s1")

    await model.keepTapped()
    model.markForDeletionTapped()
    #expect(!gates.hasEntered(1))
    #expect(model.markedIDs.isEmpty)

    gates.open(0)
    await keep.value
    #expect(photoStore.keepInCaptureInboxCount == 1)
    #expect(photoStore.keptInCaptureInboxIDs == ["s1"])
    #expect(model.keepingID == nil)
    #expect(model.content.ids == ["s2", "s3"])
    #expect(model.keptCount == 1)

    await cancelAndWait(appear)
  }

  @Test("보관 결과가 다음 방문을 연 뒤 도착하면 새 방문의 수·알림에 반영하지 않고, 새 방문을 다시 읽어 보관한 장을 뺀다")
  func keepResultAfterNextVisitReloads() async {
    let gates = CallGates(holding: [0])
    let photoStore = CleanupFixture.store(onKeepInCaptureInbox: { await gates.pass($0) })
    let model = CleanupFixture.inboxModel(photoStore: photoStore)
    let first = await model.open()

    let keep = Task { await model.keepTapped() }
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(first)

    let second = await model.open()
    #expect(model.content.ids == ["s1", "s2", "s3"])
    // 앞 방문의 저장이 끝나기 전에는 새 방문에서도 보관·표시를 받지 않는다.
    #expect(model.keepingID == "s1")
    await model.keepTapped()
    #expect(!gates.hasEntered(1))

    gates.open(0)
    await keep.value
    #expect(photoStore.keptInCaptureInboxIDs == ["s1"])
    #expect(model.keepingID == nil)
    // 새 방문의 첫 읽기는 저장 전에 끝났으므로, 다시 읽어야 보관한 장이 빠진다.
    await waitUntil { model.content.ids == ["s2", "s3"] }
    #expect(model.keptCount == 0)
    #expect(model.alert == nil)

    await cancelAndWait(second)
  }

  @Test("보관 실패가 다음 방문을 연 뒤 도착하면 새 방문에 알림 창을 띄우지 않고 장도 그대로 둔다")
  func keepFailureAfterNextVisitIsDropped() async {
    let gates = CallGates(holding: [0])
    let photoStore = CleanupFixture.store(
      captureInboxKeepError: .failed,
      onKeepInCaptureInbox: { await gates.pass($0) }
    )
    let model = CleanupFixture.inboxModel(photoStore: photoStore)
    let first = await model.open()

    let keep = Task { await model.keepTapped() }
    await waitUntil { gates.hasEntered(0) }
    await cancelAndWait(first)

    let second = await model.open()
    gates.open(0)
    await keep.value

    #expect(model.alert == nil)
    #expect(model.keepingID == nil)
    #expect(photoStore.keptInCaptureInboxIDs.isEmpty)
    #expect(model.content.ids == ["s1", "s2", "s3"])

    await cancelAndWait(second)
  }
}
