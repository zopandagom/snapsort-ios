import Foundation

/// 보관함 사진의 위치·날짜로 여행을 찾는다 (docs/ARCHITECTURE.md §4). 이미지 라벨은 보지 않는다.
/// 여행은 "평소와 다른 곳"이라서 같은 사람의 다른 사진에서 자주 가는 지역을 먼저 정하고, 그 밖에서 찍은 사진을 날짜로 묶는다.
/// 자주 가는 지역은 판정 안에서만 쓰고 저장하거나 보여 주지 않는다. 기준 수치는 임시이며 정확도 측정 작업에서 조정한다.
public enum TravelDetector {
  /// 지역 칸의 크기(도). 위도·경도 모두 이 간격으로 나눈다. 위도 방향 약 20km 이고, 경도 방향은 고위도로 갈수록 좁아진다(서울 약 16km).
  static let regionSize = 0.18
  /// 자주 가는 지역인지 볼 때 방문 앞뒤로 살피는 달 수. 보관함 전체로 보면 몇 년에 걸쳐 같은 곳에 세 번 간
  /// 여행지도 자주 가는 지역이 되므로, 그 방문 무렵에 자주 갔는지 본다.
  static let frequentWindowMonths = 3
  /// 자주 가는 지역으로 보는, 살피는 기간 안의 방문 수. 방문은 한 칸과 맞닿은 칸에서 빈 날 `maximumEmptyDays` 까지
  /// 이어 찍은 기간 중 그 칸에 들른 날들이다(`Visit`).
  /// 사진 수나 날 수로 세면 여행에서 많이 찍거나 오래 머문 곳이 자주 가는 지역이 되고, 달로 세면 달 경계에 걸친 여행
  /// 하나가 두 달로 세어지므로 방문으로 센다.
  static let minimumFrequentVisits = 3
  /// 방문 한 번만으로 자주 가는 지역으로 보는, 방문 첫날과 마지막 날 사이의 날 수. 매일 사진을 찍는 집은 방문 하나로
  /// 이어지므로 이 조건으로 잡는다. 이보다 오래 머문 곳은 여행지가 아니라 생활한 곳으로 본다.
  static let minimumFrequentStayDays = 60
  /// 같은 여행으로 잇는, 여행지 사진이 없는 날의 최대 수.
  static let maximumEmptyDays = 1
  /// 여행으로 보는 최소 사진 수. 당일치기도 여행이지만 지나가며 찍은 몇 장은 거른다.
  static let minimumPhotoCount = 5

  /// 여행 목록. 시작 시각 순이다.
  /// - 자주 가는 지역: 사진이 속한 방문의 앞뒤 `frequentWindowMonths` 개월 안에 방문이 `minimumFrequentVisits` 번 이상
  ///   있거나 `minimumFrequentStayDays` 일 이상 이어진 방문이 있는 지역, 그리고 보관함 전체에서 사진을 찍은 날이 가장
  ///   많은 지역. 칸 경계 바로 너머를 여행으로 보지 않도록 맞닿은 칸의 방문도 함께 본다.
  ///   방문 단위로 판정하므로 한 방문 안의 사진은 모두 같은 답을 받아 여행이 중간에 잘리지 않는다.
  /// - 여행: 자주 가는 지역 밖에서 찍은 사진을, 빈 날 `maximumEmptyDays` 까지 이어 묶는다.
  ///   중간에 자주 가는 지역에서 찍은 사진이 있으면(같은 날이어도) 돌아온 것으로 보고 끊는다.
  /// - 위치나 날짜가 없는 이미지(스크린샷·저장 이미지 등)는 판정에 쓰지 않는다.
  /// - Parameter calendar: 날짜·달을 나누는 달력. 앱은 기기 달력을 넘긴다.
  public static func trips(in assets: [ImageAsset], calendar: Calendar) -> [Trip] {
    let photos = assets.compactMap { LocatedPhoto($0, calendar: calendar) }
      .sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    let frequentRegions = FrequentRegions(photos: photos, calendar: calendar)

    var trips: [Trip] = []
    var current: [LocatedPhoto] = []
    func finishTrip() {
      if current.count >= self.minimumPhotoCount, let trip = Trip(current) {
        trips.append(trip)
      }
      current = []
    }

    // 마지막 여행지 사진 뒤에 자주 가는 지역에서 찍은 사진이 있었는지. 같은 날 돌아왔어도 다음 여행지 사진은 새 여행이다.
    var returned = false
    for photo in photos {
      if frequentRegions.contains(photo) {
        returned = true
        continue
      }
      if let last = current.last {
        let dayGap = calendar.dateComponents([.day], from: last.day, to: photo.day).day ?? 0
        if returned || dayGap > self.maximumEmptyDays + 1 {
          finishTrip()
        }
      }
      returned = false
      current.append(photo)
    }
    finishTrip()
    return trips
  }
}

/// 판정에 쓰는 사진: 유효한 위치와 날짜가 모두 있는 이미지.
private struct LocatedPhoto {
  let id: String
  let date: Date
  /// 촬영한 날의 시작 시각.
  let day: Date
  let coordinate: Coordinate
  let region: Region

  init?(_ asset: ImageAsset, calendar: Calendar) {
    guard let date = asset.creationDate, let coordinate = asset.coordinate else { return nil }
    // 칸 번호로 바꿀 때 NaN·무한대에서 멈추지 않도록 유효한 위도·경도만 쓴다.
    guard (-90 ... 90).contains(coordinate.latitude), (-180 ... 180).contains(coordinate.longitude) else {
      return nil
    }
    self.id = asset.id
    self.date = date
    self.day = calendar.startOfDay(for: date)
    self.coordinate = coordinate
    self.region = Region(coordinate)
  }
}

/// 한 칸의 방문: 그 칸과 맞닿은 칸에서 빈 날 `TravelDetector.maximumEmptyDays` 까지 이어 사진을 찍은 기간 중, 그 칸에서
/// 찍은 첫날과 마지막 날. 달 경계를 넘거나 맞닿은 칸을 오가도 한 번의 방문이다.
private struct Visit {
  let firstDay: Date
  let lastDay: Date
}

/// 사진이 자주 가는 지역에서 찍혔는지 답한다. 같은 곳이라도 시기에 따라 답이 다르다(이사, 반복 여행).
private struct FrequentRegions {
  private let calendar: Calendar
  /// 칸별 방문. 서로 겹치지 않고 시간 순이라 첫날과 마지막 날이 모두 정렬되어 있다.
  private let visits: [Region: [Visit]]
  /// 칸별로 사진을 찍은 날이 속한 방문의 위치.
  private let visitIndices: [Region: [Date: Int]]
  /// 보관함 전체에서 사진을 찍은 날이 가장 많은 칸. 보관함이 짧거나 집 사진이 드물어 기간별 기준을 못 채워도
  /// 집 근처 사진이 여행이 되지 않도록 시기와 관계없이 자주 가는 지역으로 본다.
  private let mostVisited: Region?

  init(photos: [LocatedPhoto], calendar: Calendar) {
    var days: [Region: Set<Date>] = [:]
    for photo in photos {
      days[photo.region, default: []].insert(photo.day)
    }
    var visits: [Region: [Visit]] = [:]
    var visitIndices: [Region: [Date: Int]] = [:]
    for (region, ownDays) in days {
      // 맞닿은 칸을 오가며 다닌 여행이 이 칸의 방문 여러 번으로 세어지지 않도록, 맞닿은 칸에서 찍은 날까지 이어 본다.
      let nearbyDays = region.withNeighbors.reduce(into: Set<Date>()) { $0.formUnion(days[$1] ?? []) }
      var regionVisits: [Visit] = []
      var indices: [Date: Int] = [:]
      var current: Visit?
      var previousDay: Date?
      for day in nearbyDays.sorted() {
        if let previousDay,
           Self.days(from: previousDay, to: day, calendar: calendar) > TravelDetector.maximumEmptyDays + 1,
           let visit = current
        {
          regionVisits.append(visit)
          current = nil
        }
        if ownDays.contains(day) {
          current = Visit(firstDay: current?.firstDay ?? day, lastDay: day)
          indices[day] = regionVisits.count
        }
        previousDay = day
      }
      if let current {
        regionVisits.append(current)
      }
      visits[region] = regionVisits
      visitIndices[region] = indices
    }
    self.calendar = calendar
    self.visits = visits
    self.visitIndices = visitIndices
    // 날 수가 같으면 결과가 실행마다 바뀌지 않도록 칸 순서(남쪽, 같은 위도면 서쪽)가 앞선 칸을 고른다.
    self.mostVisited = days.max { lhs, rhs in
      lhs.value.count == rhs.value.count ? rhs.key < lhs.key : lhs.value.count < rhs.value.count
    }?.key
  }

  /// 사진이 속한 방문 무렵, 사진의 칸이나 맞닿은 칸이 자주 가는 지역이면 true.
  func contains(_ photo: LocatedPhoto) -> Bool {
    guard let index = self.visitIndices[photo.region]?[photo.day], let visit = self.visits[photo.region]?[index] else {
      return false
    }
    let window = TravelDetector.frequentWindowMonths
    guard let start = self.calendar.date(byAdding: .month, value: -window, to: visit.firstDay),
          let end = self.calendar.date(byAdding: .month, value: window, to: visit.lastDay)
    else {
      return false
    }
    return photo.region.withNeighbors.contains { self.isFrequent($0, from: start, to: end) }
  }

  private func isFrequent(_ region: Region, from start: Date, to end: Date) -> Bool {
    if region == self.mostVisited {
      return true
    }
    guard let regionVisits = self.visits[region] else { return false }
    let lower = regionVisits.partitioningIndex { $0.lastDay >= start }
    let upper = regionVisits.partitioningIndex { $0.firstDay > end }
    let overlapping = regionVisits[lower ..< upper]
    if overlapping.count >= TravelDetector.minimumFrequentVisits {
      return true
    }
    return overlapping.contains {
      Self.days(from: $0.firstDay, to: $0.lastDay, calendar: self.calendar) >= TravelDetector.minimumFrequentStayDays
    }
  }

  private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
    calendar.dateComponents([.day], from: start, to: end).day ?? 0
  }
}

private extension Array {
  /// 앞쪽은 모두 `belongsInSecondPartition` 이 false, 뒤쪽은 모두 true 인 배열에서 처음 true 인 위치.
  func partitioningIndex(where belongsInSecondPartition: (Element) -> Bool) -> Int {
    var low = 0
    var high = self.count
    while low < high {
      let middle = (low + high) / 2
      if belongsInSecondPartition(self[middle]) {
        high = middle
      } else {
        low = middle + 1
      }
    }
    return low
  }
}

/// 위도·경도를 `TravelDetector.regionSize` 도 간격으로 나눈 칸.
private struct Region: Hashable, Comparable {
  let row: Int
  let column: Int

  init(row: Int, column: Int) {
    self.row = row
    self.column = column
  }

  init(_ coordinate: Coordinate) {
    self.row = Int((coordinate.latitude / TravelDetector.regionSize).rounded(.down))
    self.column = Int((coordinate.longitude / TravelDetector.regionSize).rounded(.down))
  }

  /// 이 칸과 맞닿은 여덟 칸.
  var withNeighbors: [Region] {
    (-1 ... 1).flatMap { rowOffset in
      (-1 ... 1).map { columnOffset in Region(row: self.row + rowOffset, column: self.column + columnOffset) }
    }
  }

  static func < (lhs: Region, rhs: Region) -> Bool {
    (lhs.row, lhs.column) < (rhs.row, rhs.column)
  }
}

private extension Trip {
  /// 중심점은 사진이 가장 많은 칸 안의 사진 평균이다. 칸 안 점들의 평균은 그 칸을 벗어나지 않으므로
  /// 여행지가 여러 곳이어도 중심점이 자주 가는 지역(집 근처)이나 여행지 사이 바다에 떨어지지 않는다.
  init?(_ photos: [LocatedPhoto]) {
    guard let first = photos.first, let last = photos.last else { return nil }
    let byRegion = Dictionary(grouping: photos, by: \.region)
    // 사진 수가 같으면 칸 순서(남쪽, 같은 위도면 서쪽)가 앞선 칸을 고른다.
    let mainRegion = byRegion.max { lhs, rhs in
      lhs.value.count == rhs.value.count ? rhs.key < lhs.key : lhs.value.count < rhs.value.count
    }
    guard let mainPhotos = mainRegion?.value else { return nil }
    let count = Double(mainPhotos.count)
    self.init(
      assetIDs: photos.map(\.id),
      startDate: first.date,
      endDate: last.date,
      center: Coordinate(
        latitude: mainPhotos.map(\.coordinate.latitude).reduce(0, +) / count,
        longitude: mainPhotos.map(\.coordinate.longitude).reduce(0, +) / count
      )
    )
  }
}
