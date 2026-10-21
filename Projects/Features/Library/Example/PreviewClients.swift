import IndexingInterface
import IndexingTesting
import NotificationInterface
import NotificationTesting

extension IndexingClientFake {
  /// 128장 중 40장을 분석하고 2장을 미룬 상태로 계속 분석 중이다.
  static let previewInProgress = IndexingClientFake(
    progress: [IndexingProgress(totalCount: 128, indexedCount: 40, skippedCount: 2)],
    finishesAfterProgress: false
  )

  /// 128장 중 40장에서 멈춘 상태. "다시 시도"를 누르면 다시 시작했다가 또 멈춘다.
  static let previewStopped = IndexingClientFake(
    progress: [IndexingProgress(totalCount: 128, indexedCount: 40, skippedCount: 0)]
  )

  /// 모두 분류하고 캡처 34장 중 12장의 글자를 읽었고 1장은 읽지 못해 미룬 상태로 계속 읽는 중이다.
  static let previewRecognizingText = IndexingClientFake(
    progress: [IndexingProgress(
      totalCount: 128,
      indexedCount: 126,
      skippedCount: 2,
      pendingTextCount: 21,
      recognizedTextCount: 12,
      skippedTextCount: 1
    )],
    finishesAfterProgress: false
  )

  /// 글자를 읽다가 21장을 남기고 멈춘 상태.
  static let previewTextStopped = IndexingClientFake(
    progress: [IndexingProgress(
      totalCount: 128,
      indexedCount: 128,
      skippedCount: 0,
      pendingTextCount: 21,
      recognizedTextCount: 12
    )]
  )

  /// 모두 분석해 진행률을 숨기고, 읽지 못해 미룬 8장(1단계 5장 + 글자 3장)만 안내하는 상태.
  static let previewFinished = IndexingClientFake(
    progress: [IndexingProgress(
      totalCount: 128,
      indexedCount: 123,
      skippedCount: 5,
      recognizedTextCount: 30,
      skippedTextCount: 3
    )],
    finishesAfterProgress: false
  )
}

extension NotificationClientFake {
  /// 알림을 거부했다. "설정에서 알림 켜기"를 누르면 설정 열기 횟수만 센다.
  static func previewDenied() -> NotificationClientFake {
    NotificationClientFake(authorization: .denied)
  }

  /// 권한을 정하기 전. 요청하면 허용된다. Preview 마다 새로 만들어 서로 상태를 나누지 않는다.
  static func previewNotDetermined() -> NotificationClientFake {
    NotificationClientFake(authorization: .notDetermined, authorizationAfterRequest: .authorized)
  }

  static func previewAuthorized() -> NotificationClientFake {
    NotificationClientFake(authorization: .authorized)
  }
}
