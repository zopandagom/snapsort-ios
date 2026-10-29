import Foundation

/// 교환처 규칙 (docs/ARCHITECTURE.md §4 기프티콘 추출).
/// 교환처 라벨 줄이 있으면 라벨 값만 읽고, 없으면 줄 전체가 브랜드 목록(`GifticonBrand`)의 이름인 줄과 상품명 앞 괄호 브랜드("[스타벅스] 콜드 브루")로 찾는다.
/// 틀린 교환처는 사실처럼 보이므로, 값이 다른 항목이나 안내문으로 보이거나 후보가 서로 다른 교환처면 비운다.
extension GifticonExtractor {
  /// 교환처 값의 최대 글자 수(공백 제외). 넘으면 안내문으로 본다. 임시 값이다.
  static let maximumPlaceLength = 20
  /// 라벨 뒤나 값에 있으면 교환처가 아니라 안내문으로 보는 말("교환처 사정에 따라 …", "… 수 있습니다"). 공백 없이 적는다.
  static let noticeMarkers = ["에따라", "수있", "경우"]
  /// 안내문의 종결 어미. 띄어 쓴 여러 낱말이 이것으로 끝나면 안내문이다("변경될 수 있습니다", "매장에 문의하세요").
  static let noticeEndings = ["니다", "세요", "어요", "아요", "해요", "에요", "예요"]

  /// 교환처 라벨 줄 중 안내문이 아닌 것. 라벨 뒤가 안내문이면("교환처 사정에 따라 변경될 수 있습니다") 라벨로 보지 않는다.
  /// 값 부분(`beforeRemark`)으로 판단해, 값 뒤에 붙은 괄호 덧말("교환처 : 이마트 (매장 사정에 따라 상이할 수 있습니다)")은 라벨을 막지 않는다.
  /// 괄호 덧말뿐이면 그 덧말로 판단한다("교환처 (매장 사정에 따라 다름)").
  /// 모델 보강의 교환처 판단(`hasRuleRedemptionPlaceClue`)도 같은 줄을 본다.
  static func redemptionPlaceLabelLines(
    _ lines: [RecognizedTextLine]
  ) -> [(line: RecognizedTextLine, rest: Substring)] {
    self.labeledLines(lines, labels: self.redemptionPlaceLabels).filter { !self.isNotice(self.beforeRemark($0.rest)) }
  }

  /// 교환처 라벨 줄이 있으면 OCR 순서로 보며 값을 처음 찾은 텍스트(라벨 뒤, 비었으면 라벨 오른쪽이나 아래 줄)이고, 없으면
  /// 라벨 없는 교환처(`unlabeledRedemptionPlace`)다. 라벨이 있으면 값을 못 찾아도(로고라 읽은 글자가 없음) 라벨 없는 규칙을 쓰지 않는다.
  /// 라벨 뒤에 값이 있으면 아래 줄을 보지 않는다. 괄호 묶음 하나뿐이면(`isRemarkOnly`, "사용처 (일부 매장 제외)") 같은 줄 값이 없는 것으로
  /// 보고 아래 줄을 읽는다(덧말을 교환처로 쓰지 않는다). 괄호로 시작하는 값("(주)가나다")은 같은 줄 값이다.
  /// 값이 교환처로 보이지 않으면(`labeledPlaceValue`) 그 라벨 줄은 값을 못 찾은 것이다.
  static func redemptionPlace(in lines: [RecognizedTextLine]) -> String? {
    let labeled = self.redemptionPlaceLabelLines(lines)
    guard !labeled.isEmpty else { return self.unlabeledRedemptionPlace(in: lines) }
    for (label, rest) in labeled {
      let text = self.cleanedValue(rest) != nil && !self.isRemarkOnly(rest)
        ? Substring(rest)
        : self.valueLine(of: label, in: lines).map { Substring($0.text) }
      if let place = text.flatMap(self.labeledPlaceValue) {
        return place
      }
    }
    return nil
  }

  /// 라벨 값 텍스트의 교환처. 전체가 교환처로 보이면(`isPlaceValue`) 전체("CU (일부 매장 제외)"), 아니면 값 부분(`beforeRemark`,
  /// "이마트 (매장 사정에 따라 상이할 수 있습니다)" 의 "이마트")이고, 둘 다 아니면 nil.
  private static func labeledPlaceValue(_ text: Substring) -> String? {
    [text, self.beforeRemark(text)].lazy.compactMap { self.cleanedValue($0) }.first(where: self.isPlaceValue)
  }

  /// 값 부분: 앞에 글자나 숫자가 나온 뒤의 첫 여는 괄호("(", "（") 앞까지. 맨 앞 괄호("(주)가나다")에서는 자르지 않는다.
  /// 그런 괄호가 없으면 전체("(일부 매장 제외)" 도 전체).
  private static func beforeRemark(_ text: Substring) -> Substring {
    var hasContent = false
    for index in text.indices {
      let character = text[index]
      if hasContent, "(（".contains(character) {
        return text[..<index]
      }
      hasContent = hasContent || character.isLetter || character.isNumber
    }
    return text
  }

  /// 라벨 뒤가 괄호 묶음 하나뿐인지("(일부 매장 제외)", "(CU)"). 앞쪽 구분 기호는 건너뛰고, 닫는 괄호 뒤에 글자나 숫자가 있으면
  /// ("(주)가나다") 아니다. 닫는 괄호가 없으면 끝까지 덧말로 본다.
  private static func isRemarkOnly(_ text: Substring) -> Bool {
    let trimmed = text.drop { $0.isWhitespace || ":：-|".contains($0) }
    guard let open = trimmed.first, "(（".contains(open) else { return false }
    guard let close = trimmed.firstIndex(where: { ")）".contains($0) }) else { return true }
    return !trimmed[trimmed.index(after: close)...].contains { $0.isLetter || $0.isNumber }
  }

  /// 교환처로 볼 수 있는 값인지. 글자가 있고, 기준 길이 이하이며, 날짜·긴 숫자(쿠폰·주문 번호)가 없고, 다른 항목 단어
  /// (`otherItemWords`, "주문번호 …")로 시작하지 않고, 안내문이 아니다.
  static func isPlaceValue(_ value: String) -> Bool {
    let compact = self.compact(value).lowercased()
    return compact.contains(where: \.isLetter) && compact.count <= self.maximumPlaceLength
      && DateMention.mentions(in: value).isEmpty && !compact.contains(#/\d{4}/#)
      && !self.otherItemWords.contains { compact.hasPrefix($0) } && !self.isNotice(value)
  }

  /// 안내문인지: 띄어 쓴 여러 낱말이 종결 어미(`noticeEndings`, "…습니다", "…하세요")로 끝나거나 안내문 표현(`noticeMarkers`)이 있다.
  /// 한 낱말은 문장 끝으로 보지 않고("커피에반하다", "가나다해요"), "다"·"요" 한 글자로 끝나는 가게 이름("카페 바다")도 문장이 아니다.
  /// 앞뒤 공백과 구분 기호(": 커피에반하다")는 떼고 본다.
  static func isNotice(_ text: some StringProtocol) -> Bool {
    let trimmed = text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":：-|")))
    let compact = self.compact(trimmed)
    let body = compact.trimmingCharacters(in: CharacterSet(charactersIn: ".!…)"))
    let isSentence = trimmed.contains(where: \.isWhitespace) && self.noticeEndings.contains { body.hasSuffix($0) }
    return isSentence || self.noticeMarkers.contains { compact.contains($0) }
  }

  // MARK: - 라벨 없는 교환처

  /// 라벨 없는 기프티콘의 교환처. 후보는 두 가지다.
  /// - 줄 전체(앞뒤 기호 제외)가 브랜드 목록의 이름인 줄("스타벅스", "신세계이마트"). 안내문 속 브랜드("스타벅스 카드에 충전")는 아니다.
  /// - 줄 맨 앞 괄호 안의 이름("[스타벅스] 콜드 브루 T")이 목록에 있거나, 같은 이름이 줄 전체인 줄이 따로 있다. 괄호만으로는
  ///   받지 않는다("[단독]", "[1+1]").
  /// 다른 후보에 포함되는 후보는 같은 교환처이거나 긴 이름의 나머지가 그 브랜드 별칭일 때만 뺀다("신세계"·"신세계이마트" 면
  /// "신세계이마트". "이마트"·"이마트24" 는 빼지 않는다, `isSubsumed`). 남은 후보가 모두 같은 교환처(같은 브랜드, 목록에 없으면
  /// 같은 이름)일 때만 가장 긴 이름의 원문 표기를 쓰고(같으면 OCR 순서로 앞), 서로 다른 교환처면("CU" 와 "GS25") 비운다.
  static func unlabeledRedemptionPlace(in lines: [RecognizedTextLine]) -> String? {
    let kept = self.unlabeledPlaceCandidates(in: lines)
    guard Set(kept.map(\.place)).count == 1 else { return nil }
    let longest = kept.reduce(kept[0]) { $1.key.count > $0.key.count ? $1 : $0 }
    return self.isPlaceValue(String(longest.text)) ? String(longest.text) : nil
  }

  /// 라벨 없는 교환처 후보(다른 후보에 포함되는 후보를 뺀 것). 비어 있지 않으면 규칙이 교환처 단서를 본 것이라, 서로 달라 비웠어도
  /// 모델 보강에 묻지 않는다(`hasRuleRedemptionPlaceClue`).
  static func unlabeledPlaceCandidates(in lines: [RecognizedTextLine]) -> [PlaceCandidate] {
    let lineKeys = Set(lines.compactMap { self.placeKey(self.trimmedPlace($0.text)) })
    var candidates: [PlaceCandidate] = []
    for line in lines {
      let text = self.trimmedPlace(line.text)
      if let key = self.placeKey(text), let brand = GifticonBrand.index(of: key) {
        candidates.append(PlaceCandidate(key: key, place: .brand(brand), text: text))
      }
      if let inner = self.bracketPrefix(line.text).map(self.trimmedPlace), let key = self.placeKey(inner) {
        if let brand = GifticonBrand.index(of: key) {
          candidates.append(PlaceCandidate(key: key, place: .brand(brand), text: inner))
        } else if lineKeys.contains(key) {
          candidates.append(PlaceCandidate(key: key, place: .name(key), text: inner))
        }
      }
    }
    return candidates.filter { candidate in
      !candidates.contains { self.isSubsumed(candidate, by: $0) }
    }
  }

  /// `candidate` 가 `other` 이름에 포함돼 뺄 후보인지. 같은 교환처("투썸" ⊂ "투썸플레이스")이거나, `other` 이름에서 `candidate` 이름을
  /// 뺀 나머지가 `other` 브랜드의 별칭일 때다("신세계이마트" 에서 "신세계" 를 빼면 이마트의 "이마트"). 이름만 겹치는 다른 교환처
  /// ("이마트" ⊂ "이마트24", 나머지 "24")는 빼지 않아 서로 다른 교환처로 비운다.
  private static func isSubsumed(_ candidate: PlaceCandidate, by other: PlaceCandidate) -> Bool {
    guard other.key != candidate.key, let range = other.key.range(of: candidate.key) else { return false }
    if other.place == candidate.place {
      return true
    }
    var remainder = other.key
    remainder.removeSubrange(range)
    guard case let .brand(brand) = other.place else { return false }
    return GifticonBrand.index(of: remainder) == brand
  }

  struct PlaceCandidate {
    let key: String
    let place: PlaceIdentity
    let text: Substring
  }

  /// 같은 교환처인지 견주는 값. 목록 브랜드는 별칭이 달라도 같고, 목록에 없는 이름은 정규화한 이름이 같아야 같다.
  enum PlaceIdentity: Hashable {
    case brand(Int)
    case name(String)
  }

  /// 앞뒤의 글자·숫자 아닌 것(공백, 글머리 기호, 괄호)을 뺀 원문.
  private static func trimmedPlace(_ text: some StringProtocol) -> Substring {
    let isPlaceCharacter = { (character: Character) in character.isLetter || character.isNumber }
    guard let start = text.firstIndex(where: isPlaceCharacter), let end = text.lastIndex(where: isPlaceCharacter) else {
      return ""
    }
    return Substring(text[start ... end])
  }

  /// 공백을 지우고 소문자로 바꾼 대조 키. 글자가 없으면 nil.
  private static func placeKey(_ text: Substring) -> String? {
    let key = self.compact(text).lowercased()
    return key.contains(where: \.isLetter) ? key : nil
  }

  /// 줄 맨 앞(앞쪽 공백 제외) 괄호 "[…]"·"【…】" 안의 텍스트. 괄호 뒤에 글자나 숫자(상품명)가 없으면 nil.
  private static func bracketPrefix(_ text: String) -> Substring? {
    let trimmed = text.drop(while: \.isWhitespace)
    let brackets: [Character: Character] = ["[": "]", "【": "】"]
    guard let open = trimmed.first, let close = brackets[open], let closeIndex = trimmed.firstIndex(of: close)
    else { return nil }
    let inner = trimmed[trimmed.index(after: trimmed.startIndex) ..< closeIndex]
    let product = trimmed[trimmed.index(after: closeIndex)...]
    return product.contains { $0.isLetter || $0.isNumber } ? inner : nil
  }
}
