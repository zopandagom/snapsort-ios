import Core
import Foundation
import Testing

struct TripMatchingTests {
  @Test("같은 여행을 찾는다")
  func findsSameTrip() {
    let trip = Self.trip(["a", "b", "c"], startHour: 0)
    let other = Self.trip(["x", "y"], startHour: 100)

    #expect(trip.bestMatch(in: [other, trip]) == trip)
  }

  @Test("사진이 늘어난 상위집합을 같은 여행으로 본다")
  func findsSuperset() {
    let trip = Self.trip(["a", "b", "c"], startHour: 0)
    let grown = Self.trip(["a", "b", "c", "d"], startHour: 0)

    #expect(trip.bestMatch(in: [grown]) == grown)
  }

  @Test("둘로 나뉘면 겹친 사진이 많은 쪽이다")
  func findsLargerPartAfterSplit() {
    let trip = Self.trip(["a", "b", "c", "d", "e"], startHour: 0)
    let first = Self.trip(["a", "b"], startHour: 0)
    let second = Self.trip(["c", "d", "e"], startHour: 30)

    #expect(trip.bestMatch(in: [first, second]) == second)
  }

  @Test("둘이 합쳐지면 합친 여행이다")
  func findsMergedTrip() {
    let trip = Self.trip(["c", "d"], startHour: 30)
    let merged = Self.trip(["a", "b", "c", "d"], startHour: 0)
    let unrelated = Self.trip(["x"], startHour: 30)

    #expect(trip.bestMatch(in: [unrelated, merged]) == merged)
  }

  @Test("겹치는 사진이 없으면 nil 이다")
  func returnsNilWithoutOverlap() {
    let trip = Self.trip(["a", "b"], startHour: 0)

    #expect(trip.bestMatch(in: [Self.trip(["x", "y"], startHour: 0)]) == nil)
    #expect(trip.bestMatch(in: []) == nil)
  }

  @Test("겹친 수가 같으면 시작 시각 차이가 작은 것, 그래도 같으면 시작이 이른 것이다")
  func tieBreaksByStartGapThenEarlierStart() {
    let trip = Self.trip(["a", "b", "c", "d"], startHour: 10)
    let far = Self.trip(["a", "b"], startHour: 40)
    let near = Self.trip(["c", "d"], startHour: 15)
    #expect(trip.bestMatch(in: [far, near]) == near)

    let before = Self.trip(["a", "b"], startHour: 5)
    let after = Self.trip(["c", "d"], startHour: 15)
    #expect(trip.bestMatch(in: [after, before]) == before)
  }

  private static func trip(_ ids: [String], startHour: Double) -> Trip {
    let start = Date(timeIntervalSince1970: 1_780_000_000 + startHour * 3600)
    return Trip(
      assetIDs: ids,
      startDate: start,
      endDate: start.addingTimeInterval(3600),
      center: Coordinate(latitude: 33.5, longitude: 126.53)
    )
  }
}
