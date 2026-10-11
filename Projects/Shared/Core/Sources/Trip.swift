import Foundation

/// 여행 판정(`TravelDetector`)이 찾은 여행 한 건 (docs/ARCHITECTURE.md §4).
/// 기간은 그동안 찍은 다른 카테고리 이미지(항공권·숙소 예약·영수증 캡처)를 여행에 묶는 데 쓴다.
public struct Trip: Sendable, Hashable {
  /// 여행지에서 찍은 사진의 식별자. 촬영 순이다.
  public let assetIDs: [String]
  /// 여행지에서 찍은 첫 사진의 촬영 시각.
  public let startDate: Date
  /// 여행지에서 찍은 마지막 사진의 촬영 시각.
  public let endDate: Date
  /// 여행지 사진이 가장 많은 지역 칸 안의 사진 좌표 평균. 장소 이름을 지오코딩할 때 이 묶음 중심점을 쓴다.
  /// 자주 가는 지역 밖의 칸에서 구하므로 집 근처 좌표가 되지 않는다.
  public let center: Coordinate

  public init(assetIDs: [String], startDate: Date, endDate: Date, center: Coordinate) {
    self.assetIDs = assetIDs
    self.startDate = startDate
    self.endDate = endDate
    self.center = center
  }
}
