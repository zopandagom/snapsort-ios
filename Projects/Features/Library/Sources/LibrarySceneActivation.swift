/// 앱이 앞에 있는지(scenePhase)와, 앱이 처음 앞으로 오기 전에 시작한 보관함 화면 진입의 기다림을 갖는다
/// (docs/ARCHITECTURE.md §4 인덱싱). `LibraryModel` 이 소유한다. 이 파일로 나눈 것은 LibraryModel 파일 길이 때문이다.
/// BG 작업이 앱을 띄워 화면이 뒤에서 생기면 화면 진입이 저장소를 읽거나 알림을 바꾸지 않게, 첫 `.active` 까지 진입을 붙잡는다.
@MainActor
final class LibrarySceneActivation {
  /// 앱이 앞에 있는지. 처음 `becameActive()` 전에는 거짓이다(앞에서 켤 때 scenePhase 첫 값은 `.inactive` 이고 `.active` 는 변화로 온다).
  /// `.inactive` 는 바꾸지 않는다.
  private(set) var isActive = false
  /// 기다리는 진입을 푸는 신호. 기다리는 진입이 있을 때만 있다.
  private var waiter: AsyncStream<Void>.Continuation?
  /// 기다림을 걸 때마다 하나씩 올린다. 끝난 지난 진입이 새 진입의 신호를 지우지 않게 한다.
  private var generation = 0

  /// 앱이 앞으로 왔다. 기다리는 진입을 푼다.
  func becameActive() {
    self.isActive = true
    self.waiter?.yield()
    self.waiter?.finish()
    self.waiter = nil
  }

  /// 앱이 뒤로 갔다. 기다리는 진입은 그대로 기다린다.
  func enteredBackground() {
    self.isActive = false
  }

  /// 다음 `becameActive()` 까지 기다린다. 풀려서 시작해도 되면 참이다.
  /// 부른 Task 가 취소되거나(화면이 사라짐) 새 진입이 기다림을 걸면(다른 화면 인스턴스) 거짓으로 끝나, 그 진입은 아무것도 시작하지 않는다.
  func waitUntilActive() async -> Bool {
    self.waiter?.finish()
    self.generation += 1
    let generation = self.generation
    let (signals, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.waiter = continuation
    defer {
      if generation == self.generation {
        self.waiter = nil
      }
    }
    for await _ in signals {
      return !Task.isCancelled
    }
    return false
  }
}

public extension LibraryModel {
  /// 앱이 앞에 있는지(scenePhase). 처음 `sceneBecameActive()` 전에는 거짓이다. 거짓인 동안 화면 진입(`onAppear()`)은 시작을 미루고
  /// 날짜 변경(`dayChanged()`)은 무시한다(BG 작업이 앱을 띄우거나 깨울 때 저장소를 읽지 않게, docs/ARCHITECTURE.md §4 인덱싱).
  /// LibraryView 도 이 값으로 날짜·시간대 변경을 다른 Model 에 넘길지 정한다.
  var isSceneActive: Bool {
    self.sceneActivation.isActive
  }
}
