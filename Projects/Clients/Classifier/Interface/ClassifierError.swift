/// 모델로 해석하지 못한 이유.
public enum ClassifierError: Error, Equatable {
  /// 호출한 Task 가 취소됐다. 받는 쪽은 결과를 남기지 않는다.
  case cancelled
  /// 모델을 지금 쓸 수 없다(미지원 기기, Apple Intelligence 꺼짐, 모델 다운로드 중, 요청 도중 쓸 수 없게 됨). 실패로 세지 않는다.
  case unavailable
  /// 이 입력에서 실패했다(가드레일·거절·문맥 초과·미지원 언어·형식 불일치·속도 제한 등).
  case failed
}
