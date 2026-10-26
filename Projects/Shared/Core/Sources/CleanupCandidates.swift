/// 정리 화면 후보 한 장 (docs/ARCHITECTURE.md §4 정리 도우미). 이미지와 후보 종류별 부가 정보를 담는다.
public struct CleanupCandidate: Sendable, Hashable, Identifiable {
  /// 후보 종류별 부가 정보. 지난 탑승권·예약·송장(후속 작업)은 여기에 case 를 더한다.
  public enum Detail: Sendable, Hashable {
    case gifticon(GifticonListItem)
    /// 비슷한 사진 묶음의 한 장. 남길 장이면 true(기본 선택하지 않는다).
    case similarPhoto(isKept: Bool)
  }

  public let asset: ImageAsset
  public let detail: Detail
  /// 방문의 첫 읽기에서 기본으로 고를지. 만료됨 섹션에서 만료일이 모델 추정이면, 비슷한 사진에서 남길 장이면 false.
  public let isSelectedByDefault: Bool

  public var id: ImageAsset.ID { self.asset.id }

  /// 기프티콘 후보면 그 항목. 사진 상세(`PhotoDetailRoute.gifticon`)에 넘긴다.
  public var gifticon: GifticonListItem? {
    if case let .gifticon(item) = self.detail {
      return item
    }
    return nil
  }

  /// 비슷한 사진 묶음에서 남길 장인지.
  public var isKept: Bool {
    if case .similarPhoto(isKept: true) = self.detail {
      return true
    }
    return false
  }

  public init(gifticon item: GifticonListItem, isSelectedByDefault: Bool) {
    self.asset = item.asset
    self.detail = .gifticon(item)
    self.isSelectedByDefault = isSelectedByDefault
  }

  /// 남길 장은 기본 선택하지 않고 나머지는 기본 선택한다.
  public init(similarPhoto asset: ImageAsset, isKept: Bool) {
    self.asset = asset
    self.detail = .similarPhoto(isKept: isKept)
    self.isSelectedByDefault = !isKept
  }
}

/// 섹션 안의 후보 묶음. 기프티콘 섹션은 제목 없는 묶음 하나, 비슷한 사진은 사진 묶음마다 하나.
public struct CleanupCandidateGroup: Sendable, Hashable, Identifiable {
  /// 첫 후보 식별자.
  public let id: ImageAsset.ID
  /// 비어 있지 않다.
  public let candidates: [CleanupCandidate]

  public init(id: ImageAsset.ID, candidates: [CleanupCandidate]) {
    self.id = id
    self.candidates = candidates
  }
}

public struct CleanupSection: Sendable, Hashable, Identifiable {
  /// 섹션 종류. 지난 탑승권·예약·송장(후속 작업)은 여기에 case 를 더한다.
  public enum Kind: Sendable, Hashable, CaseIterable {
    case expiredGifticons
    case usedGifticons
    case similarPhotos
  }

  public let kind: Kind
  /// 비어 있지 않다.
  public let groups: [CleanupCandidateGroup]

  public var id: Kind { self.kind }

  /// 묶음 순서대로 이은 후보.
  public var candidates: [CleanupCandidate] { self.groups.flatMap(\.candidates) }

  /// "모두 선택"이 고르는 후보: 비슷한 사진은 남길 장을 뺀 것, 그 밖은 전부.
  /// 한 번 눌러 묶음을 통째로 지우는 실수를 막는다(남길 장도 하나씩은 고를 수 있다).
  public var bulkSelectableIDs: Set<ImageAsset.ID> {
    Set(self.candidates.filter { !$0.isKept }.map(\.id))
  }

  /// 제목 없는 묶음 하나로 둔다(기프티콘 섹션). 후보가 없으면 묶음도 없다.
  public init(kind: Kind, candidates: [CleanupCandidate]) {
    self.init(
      kind: kind,
      groups: candidates.first.map { [CleanupCandidateGroup(id: $0.id, candidates: candidates)] } ?? []
    )
  }

  public init(kind: Kind, groups: [CleanupCandidateGroup]) {
    self.kind = kind
    self.groups = groups
  }
}

public struct CleanupSections: Sendable, Hashable {
  /// 화면 순서(만료됨 → 사용함 → 비슷한 사진). 빈 섹션은 뺀다.
  public let sections: [CleanupSection]
  /// 후보에서 뺀 미사용 확인 중(추출 대기·OCR 대기) 기프티콘 수. 화면 안내용.
  public let checkingGifticonCount: Int
  /// 비슷한 사진 대상인데 아직 지금 버전 특징 벡터가 없는 사진 수. 화면 안내용. 벡터를 쓸 수 없는 기기면 0 이다.
  public let uncomparedPhotoCount: Int

  public var candidateIDs: Set<ImageAsset.ID> {
    Set(self.sections.flatMap { $0.candidates.map(\.id) })
  }

  public var isEmpty: Bool { self.sections.isEmpty }

  public init(sections: [CleanupSection], checkingGifticonCount: Int, uncomparedPhotoCount: Int = 0) {
    self.sections = sections
    self.checkingGifticonCount = checkingGifticonCount
    self.uncomparedPhotoCount = uncomparedPhotoCount
  }

  /// 기프티콘 규칙:
  /// - 사용함(`isUsed`): 상태와 관계없이 "사용함" 섹션, 기본 선택. 최신순(`ImageMonthSection.isNewer`).
  /// - 미사용 `.checking`: 후보 아님, `checkingGifticonCount` 에 센다.
  /// - 미사용 `.extracted` 이고 만료일이 있고 `today.days(until: expiry) < 0`: "만료됨" 섹션.
  ///   기본 선택 = `!item.estimatedFields.contains(.expiryDate)`. 순서는 `GifticonExpirySection` 의 만료됨과 같다(최근 만료부터, 같으면 최신순).
  /// - 그 밖(만료일 없음, 오늘 이후 만료, 오늘 만료): 후보 아님.
  /// 한 장은 한 섹션에만 든다(사용함이 먼저).
  ///
  /// 비슷한 사진: `similarPhotoGroups`(`SimilarPhotoGrouping.groups`) 순서 그대로 묶음마다 하나, 남길 장은 기본 선택하지 않는다.
  /// 기프티콘은 묶기 입력에서 빼서 넘긴다(부르는 쪽이 `excluding` 에 기프티콘 전부를 넘긴다). 그래서 두 종류가 겹치지 않는다.
  public static func make(
    gifticons items: [GifticonListItem],
    today: LocalDate,
    similarPhotoGroups: [SimilarPhotoGroup] = [],
    uncomparedPhotoCount: Int = 0
  ) -> CleanupSections {
    var expired: [(LocalDate, GifticonListItem)] = []
    var used: [GifticonListItem] = []
    var checkingCount = 0
    for item in items {
      if item.isUsed {
        used.append(item)
        continue
      }
      switch item.status {
      case .checking:
        checkingCount += 1
      case let .extracted(info):
        if let expiryDate = info.expiryDate, today.days(until: expiryDate) < 0 {
          expired.append((expiryDate, item))
        }
      }
    }
    let newer: (GifticonListItem, GifticonListItem) -> Bool = { ImageMonthSection.isNewer($0.asset, than: $1.asset) }
    let expiredCandidates = expired
      .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : newer($0.1, $1.1) }
      .map { CleanupCandidate(gifticon: $0.1, isSelectedByDefault: !$0.1.estimatedFields.contains(.expiryDate)) }
    let usedCandidates = used.sorted(by: newer).map { CleanupCandidate(gifticon: $0, isSelectedByDefault: true) }
    let similarGroups = similarPhotoGroups.map { group in
      CleanupCandidateGroup(
        id: group.id,
        candidates: group.photos.map { CleanupCandidate(similarPhoto: $0, isKept: $0.id == group.keptID) }
      )
    }
    let sections: [CleanupSection] = [
      CleanupSection(kind: .expiredGifticons, candidates: expiredCandidates),
      CleanupSection(kind: .usedGifticons, candidates: usedCandidates),
      CleanupSection(kind: .similarPhotos, groups: similarGroups),
    ]
    return CleanupSections(
      sections: sections.filter { !$0.groups.isEmpty },
      checkingGifticonCount: checkingCount,
      uncomparedPhotoCount: uncomparedPhotoCount
    )
  }
}
