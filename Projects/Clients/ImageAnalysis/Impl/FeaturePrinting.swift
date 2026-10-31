import Core
import Foundation
import Synchronization
import Vision

/// Vision 특징 벡터 요청의 설정·변환·쓸 수 있음 (docs/ARCHITECTURE.md §4 정리 도우미). 시한은 세션 큐(`VisionSession.timeout`)에 있다.
enum FeaturePrinting {
  /// 요청 revision(`VisionSession` 의 `VNGenerateImageFeaturePrintRequest`). 바꾸면 `ImageFeaturePrint.version` 을 올린다(테스트가
  /// 대조한다).
  /// 새 API `GenerateImageFeaturePrintRequest(.revision2)` 로 만든 저장 벡터와 같은 판이다(docs/ARCHITECTURE.md §4 인덱싱).
  static let revision = VNGenerateImageFeaturePrintRequestRevision2
  /// `revision` 의 번호. `ImageFeaturePrint.version / 10_000` 과 같아야 한다.
  static let revisionNumber = 2

  /// 이 기기에서 특징 벡터를 만들 수 있는지. 시뮬레이터는 Vision 이 실패하거나 멈추거나 모든 사진에 같은 벡터를 준다.
  /// 이 상수만 조건부로 두고 Vision 호출 코드는 늘 컴파일해, 시뮬레이터·CI 빌드도 실기기 경로를 검사한다.
  static let isSupportedDevice: Bool = {
    #if targetEnvironment(simulator)
      false
    #else
      true
    #endif
  }()

  /// 지금 쓸 수 있는지와 앱 활성 상태. 요청이 시한을 넘기면 앞·뒤 차단을 걸어 프로세스가 끝날 때까지 두고, 막힌 동안 요청은 Vision 을 부르지 않는다.
  /// 프로세스에 하나라 같은 프로세스의 모든 `ImageAnalysisClientImpl` 값이 같이 본다.
  /// 테스트는 이 값을 바꾸지 않는다(같은 프로세스의 Impl 테스트끼리 나눈다). 바꾸는 판정은 값 타입 `FeaturePrintAvailability` 로만
  /// 테스트한다(`ImageAnalysisClientImpl.appActivityChanged` 도 이 값을 바꾸므로 Impl 테스트에서 부르지 않는다).
  /// 세션 자리(`VisionSessions`)의 잠금과 겹쳐 쥐지 않는다(이 값을 읽고 놓은 뒤 세션 쪽을 잠근다).
  static let availability = Mutex(FeaturePrintAvailability(isSupportedDevice: Self.isSupportedDevice))

  /// Vision 결과를 Core 값으로 바꾼다. Float 원소이고 개수가 `ImageFeaturePrint.elementCount` 이고 데이터 길이가 맞을 때만 값이다.
  /// revision 2 는 Float 768 개다(실측). Double 이면 저장 형식과 달라 nil.
  static func featurePrint(data: Data, elementType: ElementType, elementCount: Int) -> ImageFeaturePrint? {
    guard elementType == .float, elementCount == ImageFeaturePrint.elementCount else {
      return nil
    }
    return ImageFeaturePrint(floatData: data)
  }
}
