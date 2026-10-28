import Core
import Foundation
import Testing

struct TripCoverTests {
  @Test("사진이 없으면 후보가 없다")
  func noPhotos() {
    #expect(Self.trip([]).coverCandidateIDs.isEmpty)
  }

  @Test("한 장이면 그 한 장이다")
  func singlePhoto() {
    #expect(Self.trip(["a"]).coverCandidateIDs == ["a"])
  }

  @Test("두 장이면 뒤쪽 가운데(둘째)·첫이다")
  func twoPhotos() {
    #expect(Self.trip(["a", "b"]).coverCandidateIDs == ["b", "a"])
  }

  @Test("세 장 이상이면 가운데·첫·마지막이다")
  func threeOrMorePhotos() {
    #expect(Self.trip(["a", "b", "c"]).coverCandidateIDs == ["b", "a", "c"])
    #expect(Self.trip(["a", "b", "c", "d", "e"]).coverCandidateIDs == ["c", "a", "e"])
  }

  @Test("짝수 장의 가운데는 count / 2 번째다")
  func evenCountMiddle() {
    #expect(Self.trip(["a", "b", "c", "d"]).coverCandidateIDs == ["c", "a", "d"])
  }

  private static func trip(_ ids: [String]) -> Trip {
    let start = Date(timeIntervalSince1970: 1_780_000_000)
    return Trip(
      assetIDs: ids,
      startDate: start,
      endDate: start.addingTimeInterval(3600),
      center: Coordinate(latitude: 33.5, longitude: 126.53)
    )
  }
}
