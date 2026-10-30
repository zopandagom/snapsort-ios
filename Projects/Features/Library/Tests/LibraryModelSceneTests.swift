import Core
import Foundation
import IndexingTesting
import NotificationInterface
import NotificationTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import Testing
@testable import LibraryFeature

/// 앱이 처음 앞으로 오기 전의 화면 진입과, 뒤에 있는 동안의 날짜 변경 (docs/ARCHITECTURE.md §4 인덱싱).
/// BG 작업이 앱을 띄워 화면이 뒤에서 생겨도 저장소를 읽거나 알림을 바꾸지 않는지 Fake 의 호출 수로 본다.
@MainActor
struct LibraryModelSceneTests {
  @MainActor
  private struct Fixture {
    let model: LibraryModel
    let photoLibrary: PhotoLibraryClientFake
    let indexing: IndexingClientFake
    let photoStore: PhotoStoreClientFake
    let notification: NotificationClientFake

    init() {
      self.photoLibrary = PhotoLibraryClientFake(currentState: .authorized)
      self.indexing = IndexingClientFake(finishesAfterProgress: false)
      self.photoStore = PhotoStoreClientFake(images: [.extractedGifticon(id: "a", expiryDate: .date(2026, 10, 29))])
      self.notification = NotificationClientFake(authorization: .authorized)
      self.model = LibraryModel(
        photoLibrary: self.photoLibrary,
        indexing: self.indexing,
        photoStore: self.photoStore,
        notification: self.notification,
        widgetTimeline: nil,
        tripPlace: nil,
        backgroundIndexing: nil,
        calendar: .seoul,
        now: { .seoul(2026, 10, 19, hour: 8) }
      )
    }

    /// 화면 진입의 네 일 중 저장소·알림·사진 보관함을 건드리는 것을 아직 하나도 시작하지 않았는지.
    func expectNothingStarted() {
      #expect(self.photoStore.categoryCoversCallCount == 0)
      #expect(self.notification.authorizationStatusCount == 0)
      #expect(self.indexing.runCount == 0)
      #expect(self.photoLibrary.imageChangesSubscriberCount == 0)
    }

    /// 개수·대표 읽기, 인덱싱 구독, 화면 진입 동기화가 각각 `count` 번 시작될 때까지 기다린다.
    func waitUntilStarted(times count: Int) async {
      await waitUntil {
        self.photoStore.categoryCoversCallCount == count && self.indexing.runCount == count
          && self.notification.authorizationStatusCount == count
      }
    }
  }

  @Test("앞으로 온 적 없이 화면에 들어오면 분류 중을 보이며 기다리고, 앞으로 오면 그때 한 번 시작한다")
  func waitsUntilFirstActive() async {
    let fixture = Fixture()
    let appear = Task { await fixture.model.onAppear() }
    await settle()

    fixture.expectNothingStarted()
    #expect(fixture.model.isIndexing)
    #expect(!fixture.model.isIndexingStopped)

    fixture.model.sceneBecameActive()
    await fixture.waitUntilStarted(times: 1)
    await settle()
    #expect(fixture.photoStore.categoryCoversCallCount == 1)
    #expect(fixture.indexing.runCount == 1)
    #expect(fixture.notification.authorizationStatusCount == 1)
    await cancelAndWait(appear)
  }

  @Test("화면이 뒤에서 생기면(첫 값 .background) 들어와도 기다리고, 앞으로 오면 시작한다")
  func waitsWhenCreatedInBackground() async {
    let fixture = Fixture()
    fixture.model.sceneEnteredBackground()
    let appear = Task { await fixture.model.onAppear() }
    await settle()

    fixture.expectNothingStarted()

    fixture.model.sceneBecameActive()
    await fixture.waitUntilStarted(times: 1)
    await cancelAndWait(appear)
  }

  @Test("이미 앞에 있으면 기다리지 않고 바로 시작한다")
  func startsImmediatelyWhenActive() async {
    let fixture = Fixture()
    fixture.model.sceneBecameActive()
    let appear = Task { await fixture.model.onAppear() }

    await fixture.waitUntilStarted(times: 1)
    await cancelAndWait(appear)
  }

  @Test("기다리는 동안 화면이 사라지면 끝나고, 그 뒤 앞으로 와도 아무것도 시작하지 않는다")
  func cancelledWhileWaitingStartsNothing() async {
    let fixture = Fixture()
    let appear = Task { await fixture.model.onAppear() }
    await settle()

    await cancelAndWait(appear)
    fixture.model.sceneBecameActive()
    await settle()

    fixture.expectNothingStarted()
  }

  @Test("기다리는 진입이 둘이면 앞 진입은 시작하지 않고 끝나고, 뒤 진입만 한 번 시작한다")
  func newerEntryReplacesWaitingEntry() async {
    let fixture = Fixture()
    let first = Task { await fixture.model.onAppear() }
    await settle()
    let second = Task { await fixture.model.onAppear() }
    // 앞 진입은 뒤 진입이 기다림을 걸면 스스로 끝난다.
    await first.value

    fixture.model.sceneBecameActive()
    await fixture.waitUntilStarted(times: 1)
    await settle()
    #expect(fixture.photoStore.categoryCoversCallCount == 1)
    #expect(fixture.indexing.runCount == 1)
    await cancelAndWait(second)
  }

  @Test("뒤에 있는 동안의 날짜 변경은 동기화하지 않고, 앞으로 올 때 동기화한다")
  func dayChangeIgnoredInBackground() async {
    let fixture = Fixture()
    fixture.model.sceneBecameActive()
    let appear = Task { await fixture.model.onAppear() }
    await fixture.waitUntilStarted(times: 1)
    await settle()

    fixture.model.sceneEnteredBackground()
    fixture.model.dayChanged()
    await settle()
    #expect(fixture.notification.authorizationStatusCount == 1)

    fixture.model.sceneBecameActive()
    await waitUntil { fixture.notification.authorizationStatusCount == 2 }
    await cancelAndWait(appear)
  }

  @Test("앞에 있는지는 앞으로 옴·뒤로 감만 바꾼다")
  func isSceneActiveFollowsScenePhase() {
    let fixture = Fixture()
    #expect(!fixture.model.isSceneActive)

    fixture.model.sceneBecameActive()
    #expect(fixture.model.isSceneActive)
    fixture.model.sceneEnteredBackground()
    #expect(!fixture.model.isSceneActive)
    fixture.model.sceneBecameActive()
    #expect(fixture.model.isSceneActive)
  }

  @Test("앞에 있다가 뒤로 간 뒤 화면이 다시 생기면 다시 기다리고, 앞으로 올 때 시작한다")
  func reappearInBackgroundWaitsAgain() async {
    let fixture = Fixture()
    fixture.model.sceneBecameActive()
    let firstAppear = Task { await fixture.model.onAppear() }
    await fixture.waitUntilStarted(times: 1)
    await cancelAndWait(firstAppear)

    fixture.model.sceneEnteredBackground()
    let secondAppear = Task { await fixture.model.onAppear() }
    await settle()
    #expect(fixture.photoStore.categoryCoversCallCount == 1)
    #expect(fixture.indexing.runCount == 1)
    #expect(fixture.notification.authorizationStatusCount == 1)
    #expect(fixture.model.isIndexing)

    fixture.model.sceneBecameActive()
    await fixture.waitUntilStarted(times: 2)
    await cancelAndWait(secondAppear)
  }
}
