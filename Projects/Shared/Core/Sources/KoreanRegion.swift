/// 한국 시·도 (docs/ARCHITECTURE.md §4 캡처 묶음 추출). rawValue 는 저장 키이므로 바꾸지 않는다.
public enum KoreanProvince: String, Sendable, Hashable, CaseIterable {
  case seoul, busan, daegu, incheon, gwangju, daejeon, ulsan, sejong, gyeonggi, gangwon
  case chungbuk, chungnam, jeonbuk, jeonnam, gyeongbuk, gyeongnam, jeju

  /// 섹션에 쓰는 짧은 이름.
  public var name: String {
    switch self {
    case .seoul: "서울"
    case .busan: "부산"
    case .daegu: "대구"
    case .incheon: "인천"
    case .gwangju: "광주"
    case .daejeon: "대전"
    case .ulsan: "울산"
    case .sejong: "세종"
    case .gyeonggi: "경기"
    case .gangwon: "강원"
    case .chungbuk: "충북"
    case .chungnam: "충남"
    case .jeonbuk: "전북"
    case .jeonnam: "전남"
    case .gyeongbuk: "경북"
    case .gyeongnam: "경남"
    case .jeju: "제주"
    }
  }
}

/// 지도 캡처의 지역 (docs/ARCHITECTURE.md §4 캡처 묶음 추출). 닫힌 목록(`KoreanAdministrativeDivisions`)에서 나온 값만 담는다.
/// 지도 위 핀을 꽂지 않으므로 좌표는 없다.
public struct KoreanRegion: Sendable, Hashable, Comparable {
  public let province: KoreanProvince
  /// 표의 시·군·구 이름. 시 안의 일반구는 그 시 이름으로 올린 값이다("분당구" → "성남시"). nil 이면 시·도만.
  public let district: String?

  /// 저장 키: "seoul" 또는 "seoul:강남구". 순서(`<`)는 이 문자열 순서다.
  public var id: String {
    if let district = self.district {
      "\(self.province.rawValue):\(district)"
    } else {
      self.province.rawValue
    }
  }

  /// 섹션 이름: "서울 강남구" 또는 "서울".
  public var title: String {
    if let district = self.district {
      "\(self.province.name) \(district)"
    } else {
      self.province.name
    }
  }

  /// 표에 있는 시·도·시·군·구 짝만 받는다(시·군·구가 그 시·도에 없거나 일반구 이름이면 nil).
  public init?(id: String) {
    let parts = id.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard let first = parts.first, let province = KoreanProvince(rawValue: String(first)) else { return nil }
    switch parts.count {
    case 1:
      self.init(province: province, district: nil)
    case 2:
      let district = String(parts[1])
      guard KoreanAdministrativeDivisions.hasDistrict(district, in: province) else { return nil }
      self.init(province: province, district: district)
    default:
      return nil
    }
  }

  init(province: KoreanProvince, district: String?) {
    self.province = province
    self.district = district
  }

  public static func < (lhs: KoreanRegion, rhs: KoreanRegion) -> Bool {
    lhs.id < rhs.id
  }
}
