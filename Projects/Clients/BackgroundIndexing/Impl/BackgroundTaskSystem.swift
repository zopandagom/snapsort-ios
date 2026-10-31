import BackgroundTasks
import UIKit

// BG 작업 스케줄러와 앱 실행 시간 빌리기를 감싸는 내부 프로토콜. 테스트가 대역을 넣어 순서를 확인한다
// (시뮬레이터는 BG 처리·계속 처리를 지원하지 않아 submit 이 `BGTaskScheduler.Error.unavailable` 이다).

/// BG 처리 작업 스케줄러.
@MainActor
protocol BackgroundTaskScheduling {
  /// 식별자의 실행 핸들러를 등록한다. Info.plist 에 없는 식별자면 false. 같은 식별자를 두 번 등록하면 앱이 죽는다.
  func register(identifier: String, handler: @escaping @MainActor (any BackgroundProcessingTask) -> Void) -> Bool
  /// 계속 처리 작업의 실행 핸들러를 구체 식별자(와일드카드 아님)로 등록한다. Info.plist 와일드카드에 맞지 않으면 false.
  func registerContinued(
    identifier: String,
    handler: @escaping @MainActor (any ContinuedProcessingTask) -> Void
  ) -> Bool
  /// 처리 요청을 제출한다. 같은 식별자로 아직 실행되지 않은 요청이 있으면 바꿔치기한다.
  func submit(identifier: String, requiresExternalPower: Bool, requiresNetworkConnectivity: Bool) throws
  /// 계속 처리 요청을 앞에서 제출한다(바로 시작 못 하면 실패). 자원은 기본(GPU 를 요청하지 않는다).
  /// 등록한 식별자로만 부른다(아니면 앱이 죽는다).
  func submitContinued(identifier: String, title: String, subtitle: String) throws
}

/// 시스템이 넘긴 BG 처리 작업.
protocol BackgroundProcessingTask: AnyObject {
  /// 시스템이 작업을 끝내기 직전에 부른다. 완료를 알리거나 시스템이 부른 뒤 nil 이 된다.
  var expirationHandler: (() -> Void)? { get set }
  func setTaskCompleted(success: Bool)
}

/// 시스템이 넘긴 계속 처리 작업. 진행 중 시스템 진행 화면에 문구와 진행률을 보인다(진행률을 보고하지 않으면 시스템이 만료한다).
protocol ContinuedProcessingTask: BackgroundProcessingTask {
  func updateTitle(_ title: String, subtitle: String)
  /// 진행률(`progress.totalUnitCount`·`completedUnitCount`).
  func updateProgress(completed: Int64, total: Int64)
}

/// 계속 처리 요청 제출 실패의 처리 구분.
enum ContinuedSubmitFailure: Equatable {
  /// 바로 돌릴 수 없음·요청 수 초과. 나중에 다시 요청할 수 있다.
  case temporary
  /// 지원 안 함·허용 안 된 식별자·알 수 없음. 이 실행에서는 다시 요청하지 않는다.
  case permanent

  init(_ error: any Error) {
    switch (error as? BGTaskScheduler.Error)?.code {
    case .immediateRunIneligible?, .tooManyPendingTaskRequests?:
      self = .temporary
    default:
      self = .permanent
    }
  }
}

/// 앱 상태와 실행 시간 빌리기.
@MainActor
protocol BackgroundExecution {
  /// 앱이 앞에 있는지(`applicationState == .active`).
  var isActive: Bool { get }
  /// 실행 시간을 빌린다. 빌리지 못하면 nil. `expiration` 은 빌린 시간이 끝나기 직전 메인에서 부른다.
  func begin(name: String, expiration: @escaping @MainActor () -> Void) -> Int?
  func end(_ identifier: Int)
}

extension BGTask: BackgroundProcessingTask {}

extension BGContinuedProcessingTask: ContinuedProcessingTask {
  func updateProgress(completed: Int64, total: Int64) {
    self.progress.totalUnitCount = total
    self.progress.completedUnitCount = completed
  }
}

struct SystemBackgroundTaskScheduler: BackgroundTaskScheduling {
  func register(identifier: String, handler: @escaping @MainActor (any BackgroundProcessingTask) -> Void) -> Bool {
    // 메인 큐로 받아 MainActor 의 조정자가 작업을 바로 다룬다.
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
      MainActor.assumeIsolated { handler(task) }
    }
  }

  func registerContinued(
    identifier: String,
    handler: @escaping @MainActor (any ContinuedProcessingTask) -> Void
  ) -> Bool {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
      MainActor.assumeIsolated {
        guard let continued = task as? BGContinuedProcessingTask else {
          task.setTaskCompleted(success: false)
          return
        }
        handler(continued)
      }
    }
  }

  func submit(identifier: String, requiresExternalPower: Bool, requiresNetworkConnectivity: Bool) throws {
    let request = BGProcessingTaskRequest(identifier: identifier)
    request.requiresExternalPower = requiresExternalPower
    request.requiresNetworkConnectivity = requiresNetworkConnectivity
    // 동기 판은 iOS 27 에서 deprecated 지만 배포 타깃 26 에서는 경고가 없다. 타깃을 27 로 올리면 async 판(`submit(_:) async throws`)으로 바꾼다.
    try BGTaskScheduler.shared.submit(request)
  }

  func submitContinued(identifier: String, title: String, subtitle: String) throws {
    // 처리 요청과 같이 동기 판을 쓴다(배포 타깃 26).
    try BGTaskScheduler.shared.submit(Self.continuedRequest(identifier: identifier, title: title, subtitle: subtitle))
  }

  /// 바로 시작하지 못하면 실패(`.fail`)하는 계속 처리 요청. 자원은 기본(GPU 요청 없음, entitlement 없음). 뒤에서 분류·벡터는
  /// 이미지 분석이 앞에서 불러 둔 요청으로 한다(docs/ARCHITECTURE.md §4 인덱싱).
  nonisolated static func continuedRequest(
    identifier: String,
    title: String,
    subtitle: String
  ) -> BGContinuedProcessingTaskRequest {
    let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
    request.strategy = .fail
    return request
  }
}

struct SystemBackgroundExecution: BackgroundExecution {
  var isActive: Bool {
    UIApplication.shared.applicationState == .active
  }

  func begin(name: String, expiration: @escaping @MainActor () -> Void) -> Int? {
    let identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
      MainActor.assumeIsolated { expiration() }
    }
    return identifier == .invalid ? nil : identifier.rawValue
  }

  func end(_ identifier: Int) {
    UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: identifier))
  }
}
