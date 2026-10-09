/// 이미지를 분석하지 못한 이유.
public enum ImageAnalysisError: Error, Equatable {
  /// 호출한 Task 가 취소되어 분석을 멈췄다. 받는 쪽은 결과를 남기지 않는다.
  case cancelled
  /// 그 밖의 실패 (잘못된 이미지, 모델 실행 실패 등).
  case failed
}
