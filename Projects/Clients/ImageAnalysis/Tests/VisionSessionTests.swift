import Testing
import Vision
@testable import ImageAnalysisImpl

/// 세션 자리 판정(`VisionSessionSlot`)과 요청 설정을 본다. 직렬 실행 도우미(`VisionWorkQueue`)는 `VisionWorkQueueTests`.
/// 프로세스 전역 `VisionSessions` 는 바꾸지 않는다(같은 프로세스의 Impl 테스트끼리 나눈다). Vision 요청은 perform 하지 않는다
/// (시뮬레이터의 Vision 은 실패하거나 멈출 수 있다, docs/CONVENTIONS.md §3).
struct VisionSessionTests {
  @Test("앞에서는 없으면 만들고 있으면 쓰며, 뒤에서는 그 종류가 준비된 세대만 쓰고, 버리면 옛 세대의 늦은 결과를 무시한다")
  func slotTransitions() {
    var slot = VisionSessionSlot()

    #expect(slot.checkout(.classify, isAppActive: true) == .create(1))
    #expect(slot.checkout(.classify, isAppActive: true) == .use(1, isFirstUse: true))
    #expect(slot.checkout(.classify, isAppActive: false) == .unavailable)

    let firstSuccess = slot.succeeded(.classify, generation: 1)
    let secondSuccess = slot.succeeded(.classify, generation: 1)
    #expect(firstSuccess)
    #expect(!secondSuccess)
    #expect(slot.checkout(.classify, isAppActive: false) == .use(1, isFirstUse: false))
    #expect(slot.checkout(.classify, isAppActive: true) == .use(1, isFirstUse: false))
    #expect(slot.checkout(.featurePrint, isAppActive: true) == .use(1, isFirstUse: true))
    #expect(slot.checkout(.featurePrint, isAppActive: false) == .unavailable)

    let discarded = slot.discard(generation: 1)
    #expect(discarded)
    #expect(slot.generation == nil)
    #expect(slot.warmed.isEmpty)
    #expect(slot.checkout(.classify, isAppActive: false) == .unavailable)
    #expect(slot.checkout(.classify, isAppActive: true) == .create(2))

    let before = slot
    let staleDiscard = slot.discard(generation: 1)
    let staleSuccess = slot.succeeded(.featurePrint, generation: 1)
    #expect(!staleDiscard)
    #expect(!staleSuccess)
    #expect(slot == before)
  }

  @Test("뒤에서 세션이 없으면 만들지 않는다")
  func backgroundDoesNotCreate() {
    var slot = VisionSessionSlot()

    #expect(slot.checkout(.classify, isAppActive: false) == .unavailable)
    #expect(slot.checkout(.featurePrint, isAppActive: false) == .unavailable)
    #expect(slot.generation == nil)
  }

  @Test("쓸 수 있는지: 상한 전 앞은 true, 뒤는 세션이 있고 그 종류가 준비됐을 때만 true")
  func availabilityTable() {
    var slot = VisionSessionSlot()
    for kind in [VisionSession.Kind.classify, .featurePrint] {
      #expect(slot.isAvailable(kind, isAppActive: true))
      #expect(!slot.isAvailable(kind, isAppActive: false))
    }

    _ = slot.checkout(.classify, isAppActive: true)
    #expect(slot.isAvailable(.classify, isAppActive: true))
    #expect(!slot.isAvailable(.classify, isAppActive: false))

    _ = slot.succeeded(.classify, generation: 1)
    #expect(slot.isAvailable(.classify, isAppActive: false))
    #expect(!slot.isAvailable(.featurePrint, isAppActive: false))
    #expect(slot.isAvailable(.featurePrint, isAppActive: true))

    _ = slot.discard(generation: 1)
    #expect(!slot.isAvailable(.classify, isAppActive: false))
    #expect(slot.isAvailable(.classify, isAppActive: true))
  }

  @Test("세션 요청은 revision 2·기본 자르기이고 이 런타임이 그 revision 을 지원한다")
  func requestConfiguration() {
    let objects = VisionSession.makeObjects()

    #expect(objects.classify.revision == VNClassifyImageRequestRevision2)
    #expect(objects.featurePrint.revision == FeaturePrinting.revision)
    #expect(objects.featurePrint.revision == 2)
    #expect(objects.featurePrint.imageCropAndScaleOption == .scaleFill)
    #expect(VNClassifyImageRequest.supportedRevisions.contains(VNClassifyImageRequestRevision2))
    #expect(VNGenerateImageFeaturePrintRequest.supportedRevisions.contains(FeaturePrinting.revision))
  }

  @Test("시한으로 버린 큐가 돌아오지 않은 채 상한에 닿으면 앞에서도 만들지 않고, 하나가 돌아오면 다시 만든다")
  func stuckQueueLimit() {
    var slot = VisionSessionSlot()
    #expect(slot.checkout(.classify, isAppActive: true) == .create(1))

    let first = slot.timedOut(generation: 1)
    #expect(first.discarded)
    #expect(!first.reachedLimit)
    #expect(slot.stuckQueues == 1)
    #expect(slot.isAvailable(.classify, isAppActive: true))
    #expect(slot.checkout(.classify, isAppActive: true) == .create(2))

    let second = slot.timedOut(generation: 2)
    #expect(second.discarded)
    #expect(second.reachedLimit)
    #expect(slot.stuckQueues == VisionSessionSlot.maxStuckQueues)
    #expect(!slot.isAvailable(.classify, isAppActive: true))
    #expect(!slot.isAvailable(.featurePrint, isAppActive: true))
    #expect(slot.checkout(.classify, isAppActive: true) == .unavailable)
    #expect(slot.generation == nil)

    slot.stuckQueueReturned()
    #expect(slot.stuckQueues == 1)
    #expect(slot.isAvailable(.classify, isAppActive: true))
    #expect(slot.checkout(.classify, isAppActive: true) == .create(3))
  }

  @Test("옛 세대 큐의 시한도 돌아오지 않은 큐로 세지만 지금 세대는 그대로 두고, 실패로 버린 것은 세지 않는다")
  func staleTimeoutCountsButKeepsGeneration() {
    var slot = VisionSessionSlot()
    _ = slot.checkout(.classify, isAppActive: true)
    _ = slot.discard(generation: 1)
    #expect(slot.stuckQueues == 0)
    #expect(slot.checkout(.classify, isAppActive: true) == .create(2))

    let stale = slot.timedOut(generation: 1)

    #expect(!stale.discarded)
    #expect(!stale.reachedLimit)
    #expect(slot.stuckQueues == 1)
    #expect(slot.generation == 2)
  }

  @Test("돌아오지 않은 큐가 없을 때 돌아왔다고 알려도 0 아래로 내려가지 않는다")
  func stuckQueueReturnedDoesNotGoNegative() {
    var slot = VisionSessionSlot()

    slot.stuckQueueReturned()

    #expect(slot.stuckQueues == 0)
    #expect(slot.canCreate)
  }
}
