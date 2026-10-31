import BackgroundTasks
import Testing
@testable import BackgroundIndexingImpl

/// 시스템 값 만들기: Info.plist 식별자 읽기와 계속 처리 요청 속성 (설계 A3·A4).
struct BackgroundIndexingSystemTests {
  @Test("허용 식별자에서 처리 작업은 와일드카드가 아닌 값, 계속 처리는 와일드카드의 * 를 run 으로 바꾼 값이다")
  func readsTaskIdentifiers() {
    let identifiers = BackgroundIndexingClientImpl.TaskIdentifiers(permitted: [
      "com.zopandagom.snapsort.indexing",
      "com.zopandagom.snapsort.continuedIndexing.*",
    ])
    let reversed = BackgroundIndexingClientImpl.TaskIdentifiers(permitted: [
      "com.zopandagom.snapsort.continuedIndexing.*",
      "com.zopandagom.snapsort.indexing",
    ])

    #expect(identifiers.processing == "com.zopandagom.snapsort.indexing")
    #expect(identifiers.continued == "com.zopandagom.snapsort.continuedIndexing.run")
    #expect(reversed == identifiers)
  }

  @Test("와일드카드가 없으면 계속 처리 식별자가 없다")
  func noContinuedWithoutWildcard() {
    let identifiers = BackgroundIndexingClientImpl.TaskIdentifiers(permitted: ["com.zopandagom.snapsort.indexing"])
    let empty = BackgroundIndexingClientImpl.TaskIdentifiers(permitted: [])

    #expect(identifiers.processing == "com.zopandagom.snapsort.indexing")
    #expect(identifiers.continued == nil)
    #expect(empty.processing == nil)
    #expect(empty.continued == nil)
  }

  @Test("계속 처리 요청은 바로 시작 못 하면 실패하고 자원은 기본(GPU 를 요청하지 않음)이며 식별자·문구를 담는다")
  func continuedRequestAttributes() {
    let request = SystemBackgroundTaskScheduler.continuedRequest(
      identifier: "com.zopandagom.snapsort.continuedIndexing.run",
      title: "제목",
      subtitle: "부제"
    )

    #expect(request.identifier == "com.zopandagom.snapsort.continuedIndexing.run")
    #expect(request.title == "제목")
    #expect(request.subtitle == "부제")
    #expect(request.strategy == .fail)
    #expect(request.requiredResources == [])
  }

  @Test("제출 오류는 바로 못 돌림·요청 수 초과만 일시적이고 나머지는 영구다")
  func classifiesSubmitFailure() {
    #expect(ContinuedSubmitFailure(BGTaskScheduler.Error(.immediateRunIneligible)) == .temporary)
    #expect(ContinuedSubmitFailure(BGTaskScheduler.Error(.tooManyPendingTaskRequests)) == .temporary)
    #expect(ContinuedSubmitFailure(BGTaskScheduler.Error(.unavailable)) == .permanent)
    #expect(ContinuedSubmitFailure(BGTaskScheduler.Error(.notPermitted)) == .permanent)
    #expect(ContinuedSubmitFailure(CocoaError(.featureUnsupported)) == .permanent)
  }
}
