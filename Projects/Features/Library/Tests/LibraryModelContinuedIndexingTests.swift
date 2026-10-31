import BackgroundIndexingInterface
import BackgroundIndexingTesting
import Foundation
import IndexingInterface
import IndexingTesting
import PhotoLibraryInterface
import PhotoLibraryTesting
import Testing
@testable import LibraryFeature

/// 계속 처리 분류: 첫 분류 자동 요청, 진행 카드의 "홈으로 나가도 계속" 버튼, 시스템 진행 화면 문구 (docs/ARCHITECTURE.md §4 인덱싱).
@MainActor
struct LibraryModelContinuedIndexingTests {
  private static let classifying = IndexingProgress(totalCount: 3, indexedCount: 1, skippedCount: 0)
  private static let classifyingMore = IndexingProgress(totalCount: 3, indexedCount: 2, skippedCount: 0)
  private static let finished = IndexingProgress(totalCount: 3, indexedCount: 3, skippedCount: 0)

  private static func model(
    photoLibrary: PhotoLibraryClientFake,
    indexing: IndexingClientFake,
    backgroundIndexing: BackgroundIndexingClientFake
  ) -> LibraryModel {
    LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: nil,
      notification: nil,
      widgetTimeline: nil,
      tripPlace: nil,
      backgroundIndexing: backgroundIndexing
    )
  }

  /// 앱이 앞으로 온 뒤 화면 진입을 시작하고, 인덱싱 구독이 선 뒤에 돌아온다.
  private static func appear(_ model: LibraryModel, indexing: IndexingClientFake) async -> Task<Void, Never> {
    model.sceneBecameActive()
    let appear = Task { await model.onAppear() }
    await waitUntil { indexing.activeRunCount == 1 }
    return appear
  }

  private static func send(_ progress: IndexingProgress, to model: LibraryModel, indexing: IndexingClientFake) async {
    indexing.sendProgress(progress)
    await waitUntil { model.indexingProgress == progress }
  }

  private static func requestCount(_ backgroundIndexing: BackgroundIndexingClientFake) -> Int {
    backgroundIndexing.events.filter { $0 == .continuedIndexingRequested }.count
  }

  /// 화면 진입이 도는 Model 과 그 인덱서.
  private struct Running {
    let model: LibraryModel
    let indexing: IndexingClientFake
    let appear: Task<Void, Never>
  }

  /// 처음부터 권한이 허용된 화면(재실행)에 진행률 하나를 보낸 상태.
  private static func indexingModel(
    backgroundIndexing: BackgroundIndexingClientFake,
    progress: IndexingProgress = Self.classifying
  ) async -> Running {
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let model = Self.model(
      photoLibrary: PhotoLibraryClientFake(currentState: .authorized),
      indexing: indexing,
      backgroundIndexing: backgroundIndexing
    )
    let appear = await Self.appear(model, indexing: indexing)
    await Self.send(progress, to: model, indexing: indexing)
    return Running(model: model, indexing: indexing, appear: appear)
  }

  // MARK: - 첫 분류 자동 요청

  @Test("이번 실행에서 권한을 받은 첫 분류는 첫 진행률에 한 번 자동 요청하고, 다음 진행률에는 다시 요청하지 않는다")
  func firstIndexingRequestsOnce() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: .authorized)
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let backgroundIndexing = BackgroundIndexingClientFake()
    let model = Self.model(photoLibrary: photoLibrary, indexing: indexing, backgroundIndexing: backgroundIndexing)
    // 온보딩 "시작"이 권한을 받는다.
    _ = await photoLibrary.requestAccess()
    let appear = await Self.appear(model, indexing: indexing)
    #expect(Self.requestCount(backgroundIndexing) == 0)

    await Self.send(Self.classifying, to: model, indexing: indexing)
    #expect(backgroundIndexing.events == [.didBecomeActive, .continuedIndexingRequested])
    #expect(backgroundIndexing.lastContinuedText != nil)
    // 요청 뒤 상태를 다시 읽어 버튼을 숨긴다.
    #expect(model.continuedIndexingState == .active)
    #expect(!model.showsContinueInBackgroundButton)
    // 자동 요청의 결과는 안내하지 않는다.
    #expect(model.continuedIndexingNotice == nil)

    await Self.send(Self.classifyingMore, to: model, indexing: indexing)
    #expect(Self.requestCount(backgroundIndexing) == 1)
    await cancelAndWait(appear)
  }

  @Test("자동 요청이 시작하지 못해도 안내하지 않고, 버튼이 남는다")
  func autoRequestFailureIsSilent() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: .authorized)
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let backgroundIndexing = BackgroundIndexingClientFake(continuedRequestResult: .temporarilyUnavailable)
    let model = Self.model(photoLibrary: photoLibrary, indexing: indexing, backgroundIndexing: backgroundIndexing)
    _ = await photoLibrary.requestAccess()
    let appear = await Self.appear(model, indexing: indexing)

    await Self.send(Self.classifying, to: model, indexing: indexing)

    #expect(Self.requestCount(backgroundIndexing) == 1)
    #expect(model.continuedIndexingNotice == nil)
    #expect(model.showsContinueInBackgroundButton)
    await cancelAndWait(appear)
  }

  @Test("처음부터 권한이 허용돼 있으면(재실행) 자동 요청하지 않고 버튼만 보인다")
  func authorizedAtLaunchDoesNotAutoRequest() async {
    let backgroundIndexing = BackgroundIndexingClientFake()
    let running = await Self.indexingModel(backgroundIndexing: backgroundIndexing)

    await Self.send(Self.classifyingMore, to: running.model, indexing: running.indexing)

    #expect(Self.requestCount(backgroundIndexing) == 0)
    #expect(running.model.showsContinueInBackgroundButton)
    await cancelAndWait(running.appear)
  }

  @Test("첫 진행률이 끝난 값(0장·이미 다 함)이면 요청하지 않고, 그 뒤 진행률에도 자동 요청하지 않는다")
  func finishedFirstProgressSkipsRequest() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: .authorized)
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let backgroundIndexing = BackgroundIndexingClientFake()
    let model = Self.model(photoLibrary: photoLibrary, indexing: indexing, backgroundIndexing: backgroundIndexing)
    _ = await photoLibrary.requestAccess()
    let appear = await Self.appear(model, indexing: indexing)

    await Self.send(Self.finished, to: model, indexing: indexing)
    #expect(Self.requestCount(backgroundIndexing) == 0)
    #expect(!model.showsContinueInBackgroundButton)

    // 그 뒤 새 사진으로 다시 분류가 돌아도 첫 분류가 아니다.
    await Self.send(Self.classifying, to: model, indexing: indexing)
    #expect(Self.requestCount(backgroundIndexing) == 0)
    #expect(model.showsContinueInBackgroundButton)
    await cancelAndWait(appear)
  }

  @Test("첫 진행률 전에 앱이 뒤로 가면, 돌아와 받은 진행률에 자동 요청하지 않는다")
  func leavingBeforeFirstProgressCancelsAutoRequest() async {
    let photoLibrary = PhotoLibraryClientFake(currentState: .notDetermined, stateAfterRequest: .authorized)
    let indexing = IndexingClientFake(finishesAfterProgress: false)
    let backgroundIndexing = BackgroundIndexingClientFake()
    let model = Self.model(photoLibrary: photoLibrary, indexing: indexing, backgroundIndexing: backgroundIndexing)
    _ = await photoLibrary.requestAccess()
    let appear = await Self.appear(model, indexing: indexing)

    model.sceneEnteredBackground()
    model.sceneBecameActive()
    await Self.send(Self.classifying, to: model, indexing: indexing)

    #expect(backgroundIndexing.events == [.didBecomeActive, .didEnterBackground, .didBecomeActive])
    #expect(model.showsContinueInBackgroundButton)
    await cancelAndWait(appear)
  }

  // MARK: - 버튼

  @Test("버튼은 요청할 수 있고 분류나 글자 읽기가 도는 동안 보인다", arguments: [
    IndexingProgress(totalCount: 3, indexedCount: 1, skippedCount: 0),
    IndexingProgress(totalCount: 3, indexedCount: 3, skippedCount: 0, pendingTextCount: 2, recognizedTextCount: 1),
  ])
  func buttonShownWhileIndexing(progress: IndexingProgress) async {
    let running = await Self.indexingModel(
      backgroundIndexing: BackgroundIndexingClientFake(),
      progress: progress
    )

    #expect(running.model.continuedIndexingState == .idle)
    #expect(running.model.showsContinueInBackgroundButton)
    await cancelAndWait(running.appear)
  }

  @Test("이미 도는 중이거나 쓸 수 없으면 버튼을 숨긴다", arguments: [
    ContinuedIndexingState.active, .unsupported,
  ])
  func buttonHiddenUnlessIdle(state: ContinuedIndexingState) async {
    let running = await Self.indexingModel(
      backgroundIndexing: BackgroundIndexingClientFake(continuedIndexingState: state)
    )

    #expect(running.model.continuedIndexingState == state)
    #expect(!running.model.showsContinueInBackgroundButton)
    await cancelAndWait(running.appear)
  }

  @Test("다 분석했거나 분류가 멈추면 버튼을 숨긴다")
  func buttonHiddenWhenFinishedOrStopped() async {
    let backgroundIndexing = BackgroundIndexingClientFake()
    let running = await Self.indexingModel(backgroundIndexing: backgroundIndexing)
    #expect(running.model.showsContinueInBackgroundButton)

    await Self.send(Self.finished, to: running.model, indexing: running.indexing)
    #expect(!running.model.showsContinueInBackgroundButton)

    await Self.send(Self.classifying, to: running.model, indexing: running.indexing)
    #expect(running.model.showsContinueInBackgroundButton)
    running.indexing.finishRuns()
    await waitUntil { running.model.isIndexingStopped }
    #expect(!running.model.showsContinueInBackgroundButton)
    await cancelAndWait(running.appear)
  }

  @Test("버튼을 누르면 한 번 요청하고 버튼이 사라지며, 다시 눌러도 요청하지 않는다")
  func tapRequestsOnce() async {
    let backgroundIndexing = BackgroundIndexingClientFake()
    let running = await Self.indexingModel(backgroundIndexing: backgroundIndexing)

    running.model.continueInBackgroundTapped()
    #expect(Self.requestCount(backgroundIndexing) == 1)
    #expect(running.model.continuedIndexingState == .active)
    #expect(!running.model.showsContinueInBackgroundButton)
    #expect(running.model.continuedIndexingNotice == nil)

    running.model.continueInBackgroundTapped()
    #expect(Self.requestCount(backgroundIndexing) == 1)
    await cancelAndWait(running.appear)
  }

  @Test("앱이 뒤에 있으면 눌러도 요청하지 않는다")
  func tapIgnoredInBackground() async {
    let backgroundIndexing = BackgroundIndexingClientFake()
    let running = await Self.indexingModel(backgroundIndexing: backgroundIndexing)
    running.model.sceneEnteredBackground()

    running.model.continueInBackgroundTapped()

    #expect(Self.requestCount(backgroundIndexing) == 0)
    await cancelAndWait(running.appear)
  }

  @Test("지금 시작할 수 없으면 다시 누르라고 안내하고 버튼을 남기며, 다시 누르면 안내를 지운다")
  func tapTemporarilyUnavailable() async {
    let backgroundIndexing = BackgroundIndexingClientFake(continuedRequestResult: .temporarilyUnavailable)
    let running = await Self.indexingModel(backgroundIndexing: backgroundIndexing)

    running.model.continueInBackgroundTapped()
    #expect(running.model.continuedIndexingNotice == .tryLater)
    #expect(running.model.showsContinueInBackgroundButton)

    backgroundIndexing.continuedRequestResult = .started
    running.model.continueInBackgroundTapped()
    #expect(Self.requestCount(backgroundIndexing) == 2)
    #expect(running.model.continuedIndexingNotice == nil)
    #expect(!running.model.showsContinueInBackgroundButton)
    await cancelAndWait(running.appear)
  }

  @Test("이 실행에서 쓸 수 없으면 버튼을 숨기고 지금 흐름을 안내한다")
  func tapUnavailable() async {
    let backgroundIndexing = BackgroundIndexingClientFake(continuedRequestResult: .unavailable)
    let running = await Self.indexingModel(backgroundIndexing: backgroundIndexing)

    running.model.continueInBackgroundTapped()

    #expect(running.model.continuedIndexingState == .unsupported)
    #expect(!running.model.showsContinueInBackgroundButton)
    #expect(running.model.continuedIndexingNotice == .unavailable)
    await cancelAndWait(running.appear)
  }

  @Test("앱이 앞으로 오면 상태를 다시 읽어, 끝난 계속 처리 뒤 버튼이 다시 보인다")
  func becomingActiveRefreshesState() async {
    let backgroundIndexing = BackgroundIndexingClientFake()
    let running = await Self.indexingModel(backgroundIndexing: backgroundIndexing)
    running.model.continueInBackgroundTapped()
    #expect(!running.model.showsContinueInBackgroundButton)

    running.model.sceneEnteredBackground()
    // 시스템 진행 화면에서 취소되는 등으로 끝났다.
    backgroundIndexing.continuedIndexingState = .idle
    running.model.sceneBecameActive()

    #expect(running.model.continuedIndexingState == .idle)
    #expect(running.model.showsContinueInBackgroundButton)
    await cancelAndWait(running.appear)
  }

  @Test("진행률을 받을 때도 상태를 다시 읽는다")
  func progressRefreshesState() async {
    let backgroundIndexing = BackgroundIndexingClientFake(continuedIndexingState: .active)
    let running = await Self.indexingModel(backgroundIndexing: backgroundIndexing)
    #expect(!running.model.showsContinueInBackgroundButton)

    backgroundIndexing.continuedIndexingState = .idle
    await Self.send(Self.classifyingMore, to: running.model, indexing: running.indexing)

    #expect(running.model.showsContinueInBackgroundButton)
    await cancelAndWait(running.appear)
  }

  @Test("Client 가 없으면 쓸 수 없는 상태라 버튼이 없다")
  func noClientIsUnsupported() {
    let model = LibraryModel(
      photoLibrary: PhotoLibraryClientFake(currentState: .authorized),
      indexing: IndexingClientFake(finishesAfterProgress: false),
      photoStore: nil,
      notification: nil,
      widgetTimeline: nil,
      tripPlace: nil,
      backgroundIndexing: nil
    )

    #expect(model.continuedIndexingState == .unsupported)
    #expect(!model.showsContinueInBackgroundButton)
  }
}

// 안내 지우기. 본문 길이 제한(type_body_length) 때문에 확장으로 나눈다.
extension LibraryModelContinuedIndexingTests {
  @Test("\"잠시 뒤 다시\" 안내는 앱이 앞으로 오거나 분류가 끝나면 지우고, 쓸 수 없음 안내는 남긴다")
  func clearsTryLaterNotice() async {
    let tryLater = BackgroundIndexingClientFake(continuedRequestResult: .temporarilyUnavailable)
    let returning = await Self.indexingModel(backgroundIndexing: tryLater)
    returning.model.continueInBackgroundTapped()
    returning.model.sceneEnteredBackground()
    returning.model.sceneBecameActive()
    #expect(returning.model.continuedIndexingNotice == nil)
    await cancelAndWait(returning.appear)

    let finishing = await Self.indexingModel(backgroundIndexing: BackgroundIndexingClientFake(
      continuedRequestResult: .temporarilyUnavailable
    ))
    finishing.model.continueInBackgroundTapped()
    await Self.send(Self.finished, to: finishing.model, indexing: finishing.indexing)
    #expect(finishing.model.continuedIndexingNotice == nil)
    await cancelAndWait(finishing.appear)

    let unavailable = await Self.indexingModel(backgroundIndexing: BackgroundIndexingClientFake(
      continuedRequestResult: .unavailable
    ))
    unavailable.model.continueInBackgroundTapped()
    unavailable.model.sceneEnteredBackground()
    unavailable.model.sceneBecameActive()
    await Self.send(Self.finished, to: unavailable.model, indexing: unavailable.indexing)
    #expect(unavailable.model.continuedIndexingNotice == .unavailable)
    await cancelAndWait(unavailable.appear)
  }
}

/// 계속 처리 분류의 시스템 진행 화면 문구(`LibraryModel.continuedIndexingText`).
@MainActor
struct LibraryModelContinuedIndexingTextTests {
  @Test("시스템 진행 화면의 제목과 부제는 카드 문구와 개수만 쓴다", arguments: [
    (ContinuedIndexingStatus(stage: .preparing, doneCount: 0, totalCount: 0), "이미지 분류 준비 중", "홈으로 나가도 이어서 분류합니다"),
    (ContinuedIndexingStatus(stage: .classifying, doneCount: 12, totalCount: 340), "이미지 분류 중", "12/340장"),
    (ContinuedIndexingStatus(stage: .recognizingText, doneCount: 3, totalCount: 40), "글자 읽는 중", "3/40장"),
    (ContinuedIndexingStatus(stage: .fetchingPlaceNames, doneCount: 1, totalCount: 3), "장소 이름 받는 중", "1/3곳"),
    (ContinuedIndexingStatus(stage: .fetchingPlaceNames, doneCount: 0, totalCount: 0), "장소 이름 받는 중", "잠시만 기다려 주세요"),
  ])
  func continuedIndexingText(status: ContinuedIndexingStatus, title: String, subtitle: String) {
    let text = LibraryModel.continuedIndexingText

    #expect(text.title(status) == title)
    #expect(text.subtitle(status) == subtitle)
  }
}
