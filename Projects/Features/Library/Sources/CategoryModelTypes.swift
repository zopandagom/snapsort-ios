import Core
import Foundation
import PhotoLibraryInterface

/// 썸네일 칸을 쓰는 화면. 한 번에 한 범위만 보관 규칙을 쓰고, 범위가 바뀌면 내용·썸네일을 비운다.
public enum ThumbnailScope: Hashable, Sendable {
  case category(ImageCategory)
  /// 보관함 검색 결과.
  case search
}

/// 카테고리 한 번 읽은 목록. 쇼핑·대화·지도는 묶음 값까지(`CaptureGroupItem`) 읽는다.
enum CategoryItems: Sendable {
  case assets([ImageAsset])
  case captureGroups([CaptureGroupItem], [CaptureGrouping])
}

/// 다시 읽은 목록을 메인 밖에서 섹션으로 만들고 지금 내용과 비교한다. 1만 장이면 정렬·달력 계산·비교가 진행률마다 되풀이되기 때문이다.
enum CategorySectioning {
  /// `current` 와 같으면 `isUnchanged` 가 참이다.
  @concurrent
  static func sections(
    of items: CategoryItems,
    calendar: Calendar,
    comparingTo current: CategorySections?
  ) async -> (sections: CategorySections, isUnchanged: Bool) {
    let sections = switch items {
    case let .assets(assets):
      CategorySections(months: ImageMonthSection.sections(of: assets, calendar: calendar), groups: [:])
    case let .captureGroups(items, groupings):
      CategorySections(
        months: ImageMonthSection.sections(of: items.map(\.asset), calendar: calendar),
        groups: Dictionary(uniqueKeysWithValues: groupings.map { grouping in
          (grouping, CaptureGroupSections.sections(of: items, grouping: grouping))
        })
      )
    }
    return (sections, sections == current)
  }
}

/// 한 번 읽은 목록으로 만든 섹션 전부. 월별과 묶기별이 같은 읽기에서 나온다.
public struct CategorySections: Equatable, Sendable {
  /// 월별 섹션. 비어 있으면 빈 카테고리.
  public let months: [ImageMonthSection]
  /// `CaptureGrouping.groupings(for:)` 의 묶기마다. 그 밖의 카테고리는 빈 사전.
  public let groups: [CaptureGrouping: [CaptureGroupSection]]

  public var isEmpty: Bool {
    self.months.isEmpty
  }
}

/// 카테고리 화면의 격자 내용.
public enum CategoryContent: Equatable {
  case loading
  /// 섹션이 비어 있으면 빈 카테고리.
  case loaded(CategorySections)
  /// 처음 읽기(또는 실패 뒤 다시 읽기)에 실패했다. 이미 섹션이 있을 때 실패하면 지난 섹션을 둔다.
  case failed
}

/// 썸네일·상세 이미지 한 장의 읽기 상태.
public enum ImageLoadState: Sendable {
  case loading
  /// `isLocalFallback` 이면 iCloud 원본 대신 기기에 있는 작은 버전이다.
  case loaded(AnalysisImage)
  case unavailable(ImageUnavailableReason)

  public var image: AnalysisImage? {
    if case let .loaded(image) = self {
      image
    } else {
      nil
    }
  }

  public var unavailableReason: ImageUnavailableReason? {
    if case let .unavailable(reason) = self {
      reason
    } else {
      nil
    }
  }

  public var isLoading: Bool {
    if case .loading = self {
      true
    } else {
      false
    }
  }
}

/// 이미지를 보일 수 없는 이유. 화면은 이유마다 다른 대체 표시를 한다.
public enum ImageUnavailableReason: Sendable, Equatable {
  /// 기기에 읽을 수 있는 버전이 없고 iCloud 에만 있다 (`ImageLoadError.notAvailableLocally`). 내려받지 않는다.
  case inCloudOnly
  /// 보관함에서 지워졌거나 제한 접근 선택에서 빠졌다 (`.notFound`).
  case notFound
  /// 그 밖의 실패 (`.failed`).
  case failed
}

/// 열린 사진 상세.
public struct PhotoDetail: Sendable {
  public let id: ImageAsset.ID
  public let state: ImageLoadState
}
