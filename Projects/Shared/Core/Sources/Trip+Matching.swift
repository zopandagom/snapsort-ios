public extension Trip {
  /// trips 중 self 와 사진이 가장 많이 겹치는 여행. 하나도 겹치지 않으면 nil.
  /// 겹친 수가 같으면 시작 시각 차이가 작은 것, 그래도 같으면 시작이 이른 것.
  /// 여행은 판정마다 통째로 다시 만들어지고 한 사진은 많아야 한 여행에 들므로, 사진 겹침이 가장 많은 여행을 같은 여행으로 본다
  /// (사진이 늘면 상위집합, 나뉘면 큰 쪽, 합쳐지면 합친 여행).
  func bestMatch(in trips: [Trip]) -> Trip? {
    let ids = Set(self.assetIDs)
    let candidates = trips
      .map { trip in (trip: trip, overlap: trip.assetIDs.filter(ids.contains).count) }
      .filter { $0.overlap > 0 }
    // `min(by:)` 의 순서는 "앞이 더 맞는다"로 둔다.
    return candidates.min { lhs, rhs in
      if lhs.overlap != rhs.overlap {
        return lhs.overlap > rhs.overlap
      }
      let lhsGap = abs(lhs.trip.startDate.timeIntervalSince(self.startDate))
      let rhsGap = abs(rhs.trip.startDate.timeIntervalSince(self.startDate))
      if lhsGap != rhsGap {
        return lhsGap < rhsGap
      }
      return lhs.trip.startDate < rhs.trip.startDate
    }?.trip
  }
}
