/// 모델로 해석하지 못한 이유.
public enum ClassifierError: Error, Equatable {
  /// 호출한 Task 가 취소됐다. 받는 쪽은 결과를 남기지 않는다.
  case cancelled
  /// 모델을 지금 쓸 수 없다(미지원 기기, Apple Intelligence 꺼짐, 모델 다운로드 중, 요청 도중 쓸 수 없게 됨). 실패로 세지 않는다.
  case unavailable
  /// 이 입력 때문에 실패했다(문맥 초과·가드레일·거절·형식 불일치).
  case failed
  /// 입력과 관계없이 시스템이 요청을 받지 않았다(속도 제한·시간 초과·세션·형식 정의 문제, 미지원 언어, 종류를 알 수 없는 오류).
  /// 이 이미지의 실패로 세지 않고 나중에 다시 묻는다. 연속 실패 차단에는 센다.
  case rejected
}
