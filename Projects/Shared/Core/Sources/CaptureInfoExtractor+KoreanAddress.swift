/// 한국 도로명·지번 주소 규칙 (docs/ARCHITECTURE.md §4 캡처 정보 추출). 줄을 공백으로 나눈 낱말 단위로 본다.
/// 주소: 시·도 → 시·군·구 1~3개 → 동·리·가나 도로명 → 건물·지번 번호.
/// - 시·도와 시·군·구는 `KoreanAdministrativeDivisions` 목록과 대조한다(끝 글자로 보면 "다시"·"축구"·"가면"을 받는다).
///   읍·면은 목록의 시·군 바로 뒤나, 시 바로 뒤에 온 일반구 뒤("용인시 처인구 포곡읍")에서만 받는다
///   (서울 강남구 같은 자치구에는 읍·면이 없다). 세종은 시·군·구가 없어 세종의 읍·면 0~1개를 거친다.
/// - 동·리("우동"), 숫자 뒤 "가"("종로1가"), 도로명("…로"·"…길", 뒤에 "166번길" 이 오면 함께. "…으로"는 뺀다).
///   짧은 "세종" 뒤에 읍·면 없이 바로 오면 "…대로"·숫자 붙은 도로명("도움1로")과 세 글자 이상 동만 받는다(시·군·구가 거르는 몫을 대신한다).
///   "세종특별자치시"·"세종시"는 행정구역 이름이라 보통 문장과 헷갈리지 않아 좁히지 않는다("세종특별자치시 갈매로 388").
/// - 번호는 낱말 전체가 "161"·"223-14"·"산 12" 꼴이어야 한다. 뒤에 "번지"나 문장 부호 ","·"."·")" 만 붙을 수 있다("30분"·"2.5"·"010-1234-5678" 은 아니다).
/// 번호 뒤의 층·호·괄호 설명은 넣지 않는다. 시·도 없이 시작한 주소("강남구 역삼동")는 찾지 않는다.
extension CaptureInfoExtractor {
  /// 한 줄에서 찾은 한국 주소. 원문의 띄어쓰기를 그대로 둔다.
  static func koreanAddresses(in text: String) -> [String] {
    let words = text.split(whereSeparator: \.isWhitespace)
    var addresses: [String] = []
    var index = 0
    while index < words.count {
      if let address = Self.koreanAddress(startingAt: index, in: words) {
        addresses.append(String(text[address.range]))
        index = address.nextIndex
      } else {
        index += 1
      }
    }
    return addresses
  }

  /// `first` 낱말에서 시작하는 주소의 원문 범위와 그 뒤 낱말 순서.
  private static func koreanAddress(
    startingAt first: Int,
    in words: [Substring]
  ) -> (range: Range<String.Index>, nextIndex: Int)? {
    guard let province = Self.province(in: words[first]) else { return nil }
    var index = first + 1
    let isStrictLocation: Bool
    let provinceName = words[first][province...]
    if KoreanAdministrativeDivisions.sejong.contains(String(provinceName)) {
      let hasTown = index < words.count && KoreanAdministrativeDivisions.sejongTowns.contains(String(words[index]))
      index += hasTown ? 1 : 0
      // 짧은 "세종"은 "세종대왕"·"세종 가면" 처럼 보통 문장에도 나와 읍·면이 없으면 좁게 본다.
      // "세종특별자치시"·"세종시"는 행정구역 이름이라 다른 시·도처럼 본다.
      isStrictLocation = !hasTown && provinceName == "세종"
    } else {
      let districtCount = Self.districtCount(startingAt: index, in: words)
      guard districtCount > 0 else { return nil }
      index += districtCount
      isStrictLocation = false
    }
    guard index < words.count,
          let locationCount = Self.locationCount(startingAt: index, in: words, isStrict: isStrictLocation)
    else { return nil }
    index += locationCount
    // "산 12" 처럼 산과 번호를 띄어 쓴 지번.
    if index + 1 < words.count, words[index] == "산" {
      index += 1
    }
    guard index < words.count, let numberEnd = Self.numberEnd(in: words[index]) else { return nil }
    return (province ..< numberEnd, index + 1)
  }

  /// 낱말이 시·도 이름이거나 한글이 아닌 글자(문장 부호 등) 뒤에 시·도 이름이 붙은 꼴("주소:서울")이면 시·도 이름이 시작하는 곳.
  /// 한글 뒤에 붙은 이름("남서울")은 시·도가 아니다.
  private static func province(in word: Substring) -> String.Index? {
    let names = KoreanAdministrativeDivisions.provinces.union(KoreanAdministrativeDivisions.sejong)
    guard let name = names.filter({ word.hasSuffix($0) }).max(by: { $0.count < $1.count }) else { return nil }
    let start = word.index(word.endIndex, offsetBy: -name.count)
    guard start == word.startIndex || !word[word.index(before: start)].isHangul else { return nil }
    return start
  }

  /// 시·군·구(목록)와 그 뒤 읍·면이 이어진 낱말 수. 최대 3개.
  private static func districtCount(startingAt first: Int, in words: [Substring]) -> Int {
    var count = 0
    while count < 3, first + count < words.count {
      let word = words[first + count]
      let isDistrict = KoreanAdministrativeDivisions.districts.contains(String(word))
      let isTown = word.wholeMatch(of: Self.townPattern) != nil
        && Self.acceptsTown(after: words[first ..< first + count])
      guard isDistrict || isTown else { break }
      count += 1
    }
    return count
  }

  /// 앞서 읽은 시·군·구 뒤에 읍·면이 올 수 있는지: 마지막이 목록의 시·군이거나, 시 바로 뒤에 온 일반구("용인시 처인구").
  private static func acceptsTown(after districts: ArraySlice<Substring>) -> Bool {
    guard let last = districts.last,
          KoreanAdministrativeDivisions.districts.contains(String(last)) else { return false }
    if last.hasSuffix("시") || last.hasSuffix("군") {
      return true
    }
    let beforeLast = districts.dropLast().last
    return last.hasSuffix("구") && beforeLast
      .map { KoreanAdministrativeDivisions.districts.contains(String($0)) && $0.hasSuffix("시") } == true
  }

  /// 동·리·가나 도로명의 낱말 수(도로명 뒤에 "166번길" 이 오면 2). 아니면 nil.
  private static func locationCount(startingAt index: Int, in words: [Substring], isStrict: Bool) -> Int? {
    let word = words[index]
    // 짧은 "세종" 뒤에 읍·면 없이 오는 동은 세 글자 이상 "…동"만 받는다(세종의 읍·면 밖 지역은 동이다. 리·"…N가"는 없다).
    if isStrict,
       word.wholeMatch(of: Self.dongOrRiPattern) != nil || word.wholeMatch(of: Self.numberedGaPattern) != nil
    {
      return word.hasSuffix("동") && word.count >= 3 ? 1 : nil
    }
    if word.wholeMatch(of: Self.numberedGaPattern) != nil || word.wholeMatch(of: Self.dongOrRiPattern) != nil {
      return 1
    }
    guard word.wholeMatch(of: Self.roadPattern) != nil, !word.hasSuffix("으로") else { return nil }
    if isStrict, !word.hasSuffix("대로"), !word.contains(where: \.isASCIIDigit) {
      return nil
    }
    let hasBranch = index + 1 < words.count && words[index + 1].wholeMatch(of: Self.branchRoadPattern) != nil
    return hasBranch ? 2 : 1
  }

  /// 낱말이 건물·지번 번호면 번호가 끝나는 곳. 뒤에는 "번지"나 문장 부호 ","·"."·")" 만 붙을 수 있다.
  private static func numberEnd(in word: Substring) -> String.Index? {
    guard let match = word.prefixMatch(of: numberPattern) else { return nil }
    let rest = word[match.range.upperBound...]
    guard rest.isEmpty || rest == "번지" || rest.allSatisfy({ ",.)".contains($0) }) else { return nil }
    return match.range.upperBound
  }

  // `Regex` 가 `Sendable` 이 아니어서 정적 저장 프로퍼티 대신 계산 프로퍼티로 둔다.
  private static var townPattern: Regex<Substring> { #/[가-힣]+(?:읍|면)/# }
  private static var numberedGaPattern: Regex<Substring> { #/[가-힣]+[0-9]+가/# }
  private static var dongOrRiPattern: Regex<Substring> { #/[가-힣0-9]+(?:동|리)/# }
  private static var roadPattern: Regex<Substring> { #/[가-힣A-Za-z0-9.]+(?:로|길)/# }
  private static var branchRoadPattern: Regex<Substring> { #/[0-9]+번?길/# }
  private static var numberPattern: Regex<Substring> { #/(?:산)?[0-9]+(?:-[0-9]+)?/# }
}
