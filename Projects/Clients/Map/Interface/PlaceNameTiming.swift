/// 장소 이름 요청의 시간 값. 여행 폴더 상세와 미리 받기(TripPlace)가 같은 값을 쓴다.
public enum PlaceNameTiming {
  /// 이름 응답을 기다리는 시간. 넘으면 기다리지 않는다(요청은 계속 가고 끝나면 캐시에 쓴다).
  /// 오프라인에서 오는 오류·시간을 실기기에서 확인하지 못해 임시로 둔 값이다.
  public static let timeout: Duration = .seconds(15)
}
