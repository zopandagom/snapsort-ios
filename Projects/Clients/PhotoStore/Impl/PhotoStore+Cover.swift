import Core
import Foundation
import PhotoStoreInterface
import SwiftData

// 보관함 화면 카드의 대표 사진 조회 (docs/ARCHITECTURE.md §4 카테고리 화면·저장소).
extension PhotoStore {
  func categoryCovers(limit: Int) throws -> [ImageCategory: [ImageAsset.ID]] {
    guard limit > 0 else {
      return [:]
    }
    var covers: [ImageCategory: [ImageAsset.ID]] = [:]
    for category in ImageCategory.allCases where category != .travel {
      let ids = try self.latestImageIDs(in: category, limit: limit)
      if !ids.isEmpty {
        covers[category] = ids
      }
    }
    let tripCovers = try self.tripCoverIDs(limit: limit)
    if !tripCovers.isEmpty {
      covers[.travel] = tripCovers
    }
    return covers
  }

  /// `assets(in:)` 의 앞 `limit` 장과 같다. SwiftData 의 문자열 정렬은 Swift `<` 가 아니라(숫자 인식·대소문자 무시)
  /// 생성일로만 상위 `limit` 장을 고르고, 경계 생성일과 같은 행은 모두 다시 읽어 `isNewer` 로 정렬한다.
  /// 경계보다 새 행은 생성일 내림차순이라 모두 첫 조회에 들어 있다.
  private func latestImageIDs(in category: ImageCategory, limit: Int) throws -> [ImageAsset.ID] {
    let rawValue = category.rawValue
    var descriptor = FetchDescriptor<StoredImage>(
      predicate: #Predicate { image in
        image.memberships.contains { $0.category == rawValue }
      },
      // 생성일 없는 행은 맨 뒤에 온다.
      sortBy: [SortDescriptor(\.creationDate, order: .reverse)]
    )
    descriptor.fetchLimit = limit
    descriptor.propertiesToFetch = [\.assetID, \.creationDate]
    let latest = try self.modelContext.fetch(descriptor)
    guard latest.count == limit, let last = latest.last else {
      return latest.sorted(by: Self.isNewer).map(\.assetID)
    }
    // nil 이면 생성일 없는 행 전부가 동률이다.
    let boundary = last.creationDate
    var tieDescriptor = FetchDescriptor<StoredImage>(
      predicate: #Predicate { image in
        image.creationDate == boundary && image.memberships.contains { $0.category == rawValue }
      }
    )
    tieDescriptor.propertiesToFetch = [\.assetID, \.creationDate]
    let ties = try self.modelContext.fetch(tieDescriptor)
    let newer = latest.filter { $0.creationDate != boundary }
    return (newer + ties).sorted(by: Self.isNewer).prefix(limit).map(\.assetID)
  }

  /// 최근 여행(시작 내림차순, 같으면 끝 내림차순) `limit` 개마다 `Trip.coverCandidateIDs` 중 저장소에 있는 첫 장.
  /// 대표가 없는 여행은 건너뛰고 더 오래된 여행으로 채우지 않는다.
  private func tripCoverIDs(limit: Int) throws -> [ImageAsset.ID] {
    var descriptor = FetchDescriptor<StoredTrip>(
      sortBy: [SortDescriptor(\.startDate, order: .reverse), SortDescriptor(\.endDate, order: .reverse)]
    )
    descriptor.fetchLimit = limit
    let candidates = try self.modelContext.fetch(descriptor)
      .map { stored in
        Trip(
          assetIDs: stored.assetIDs,
          startDate: stored.startDate,
          endDate: stored.endDate,
          center: Coordinate(latitude: stored.centerLatitude, longitude: stored.centerLongitude)
        ).coverCandidateIDs
      }
      .filter { !$0.isEmpty }
    // 후보는 여행마다 최대 3개라 나눠 조회하지 않는다.
    let ids = Array(Set(candidates.joined()))
    guard !ids.isEmpty else {
      return []
    }
    var imageDescriptor = FetchDescriptor<StoredImage>(predicate: #Predicate { ids.contains($0.assetID) })
    imageDescriptor.propertiesToFetch = [\.assetID]
    let stored = try Set(self.modelContext.fetch(imageDescriptor).map(\.assetID))
    return candidates.compactMap { $0.first(where: stored.contains) }
  }
}
