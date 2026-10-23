import Foundation

// 영수증 가게 이름: 가게 라벨(긴 라벨 → 짧은 라벨) → 라벨이 없으면 상태 막대를 뺀 첫 본문 줄 위의 줄 (docs/ARCHITECTURE.md §4 영수증 추출).
extension ReceiptExtractor {
  /// 라벨 바로 뒤 괄호 덧말로 지우지 않는 법인 표기.
  private static let corporateParentheticals: Set<String> = ["주", "유", "株", "사", "재"]
  /// 머리 영역의 최대 줄 수.
  private static let maximumHeaderLines = 6
  /// 상태 막대로 보는 위쪽 끝(정규화 좌표).
  private static let statusBarMaxY: CGFloat = 0.08

  static func storeName(in lines: [Line], context: CurrencyContext) -> String? {
    for (labels, acceptsAttached) in [(self.storeLabels, true), (self.shortStoreLabels, false)] {
      for index in lines.indices {
        guard let (_, rest) = self.lineLabel(labels, in: lines[index].original, acceptsAttached: acceptsAttached),
              let name = self.labeledStoreName(rest, at: index, in: lines)
        else { continue }
        return name
      }
    }
    return self.upperLineStoreName(in: lines, context: context)
  }

  /// 가게 라벨 뒤 값. 라벨 바로 뒤(공백 0~1)의 숫자 없는 괄호 덧말("(상호)")은 지우고, 값이 비면 같은 높이 오른쪽·바로 아래 줄을 읽는다.
  private static func labeledStoreName(_ rest: Substring, at index: Int, in lines: [Line]) -> String? {
    // 라벨 바로 뒤(공백 0~1)의 숫자 없는 괄호 덧말 하나("가맹점명(상호)", "가맹점명 (상호)")를 지운다. 법인 표기는 둔다.
    var value = rest.first == " " ? rest.dropFirst() : rest
    if let open = value.first, "([（【".contains(open),
       let close = value.firstIndex(where: { ")]）】".contains($0) })
    {
      let inner = value[value.index(after: value.startIndex) ..< close]
      if !inner.contains(where: \.isNumber), !self.corporateParentheticals.contains(String(inner)) {
        value = value[value.index(after: close)...]
      } else {
        value = rest
      }
    } else {
      value = rest
    }
    guard let cleaned = self.cleanedValue(value) else {
      return self.neighborLine(of: index, in: lines).flatMap { self.storeValue(lines[$0].original) }
    }
    if let first = self.words(cleaned).first, self.notStoreValueWords.contains(self.normalizedWord(first)) {
      return nil
    }
    return self.storeValue(cleaned)
  }

  /// 같은 높이 오른쪽의 가장 가까운 줄, 없으면 바로 아래 가장 가까운 줄(영수증 라벨로 시작하는 줄 제외).
  private static func neighborLine(of index: Int, in lines: [Line]) -> Int? {
    let box = lines[index].box
    let others = lines.indices.filter { $0 != index && !self.startsWithReceiptLabel(lines[$0].text) }
    let sameRow = others
      .filter { abs(lines[$0].box.midY - box.midY) < box.height / 2 && lines[$0].box.minX >= box.midX }
      .min { lines[$0].box.minX < lines[$1].box.minX }
    return sameRow ?? others
      .filter {
        let other = lines[$0].box
        return other.minY >= box.midY && other.minY - box.maxY <= box.height * GifticonExtractor.maximumLineGapRatio
          && other.maxX > box.minX && other.minX < box.maxX
      }
      .min { lines[$0].box.minY < lines[$1].box.minY }
  }

  /// 값을 머리말 낱말에서 끊고 정리한 뒤 가게 이름 조건을 만족하면 그 값.
  private static func storeValue(_ text: some StringProtocol) -> String? {
    let text = String(text)
    let words = self.words(text)
    let cut = words.dropFirst().first { word in
      let lowercased = word.lowercased()
      return self.storeCutWords.contains { cut in
        self.normalizedWord(word) == cut || lowercased.hasPrefix(cut) && lowercased.dropFirst(cut.count).first
          .map { $0.isNumber || ":：-".contains($0) } == true
      }
    }
    guard let value = self.cleanedValue(text[..<(cut?.startIndex ?? text.endIndex)]), self.isStoreName(value) else {
      return nil
    }
    return value
  }

  /// 가게 이름 조건: 글자 2개 이상, 40자 이하, 번호 줄·날짜·시각·머리글·문장·버튼 줄이 아니다.
  private static func isStoreName(_ value: String) -> Bool {
    value.count(where: \.isLetter) >= 2 && value.count <= 40 && !self.isNumberLine(value)
      && !self.containsDateOrTime(value) && !self.isHeaderSentenceOrButton(value)
  }

  private static func isHeaderSentenceOrButton(_ text: String) -> Bool {
    let key = self.lineKey(text)
    let compact = String(text.filter { !$0.isWhitespace }).trimmingCharacters(in: CharacterSet(charactersIn: "!"))
    let isSentence = self.sentenceEndings.contains { compact.hasSuffix($0) }
    // 취소 전표 이름·상태 문구("*** 취소 매출전표 ***", "VOID")도 머리글과 같이 가게가 아니다.
    return isSentence || self.isLine(key, joinedFrom: self.headerWords, fragments: self.headerFragments)
      || self.isLine(key, joinedFrom: self.buttonWords) || self.isLine(key, joinedFrom: self.cancelTitles)
      || self.isLine(key, joinedFrom: self.cancelStatusPhrases)
  }

  /// 번호 줄: 번호 패턴(`numberRanges`)이 있거나, 숫자 수 ≥ 글자 수, 또는 "#1234"·"No. 12" 가 들었다.
  private static func isNumberLine(_ text: String) -> Bool {
    !self.numberRanges(in: text).isEmpty || text.count(where: \.isNumber) >= text.count(where: \.isLetter)
      || text.contains(#/#\s?\d/#) || text.contains(#/(?i)\bno\.?\s?\d/#)
  }

  // MARK: - 위쪽 줄

  /// 라벨이 없을 때: 상태 막대 줄을 빼고, 위에서부터 첫 본문 줄보다 위의 줄(최대 6줄) 중 거르지 않는 첫 줄.
  private static func upperLineStoreName(in lines: [Line], context: CurrencyContext) -> String? {
    var candidates = lines
    if let bar = lines.first(where: { $0.box.minY < self.statusBarMaxY && self.isWholeTime($0.original) }) {
      candidates = candidates.filter {
        abs($0.box.midY - bar.box.midY) > bar.box.height && $0.box.midY > bar.box.midY
      }
    }
    candidates = candidates
      .filter { line in
        let key = self.lineKey(line.original)
        return !self.statusBarWords.contains(key) && key.wholeMatch(of: #/\d{1,3}%/#) == nil
      }
      .sorted { ($0.box.minY, $0.box.minX) < ($1.box.minY, $1.box.minX) }
    let header = candidates.prefix { !self.isBodyLine($0, context: context) }.prefix(self.maximumHeaderLines)
    for line in header where !self.isSkippedUpperLine(line.original) {
      if let name = self.storeValue(line.original) {
        return name
      }
    }
    return nil
  }

  /// 줄 전체가 시각("9:41", "오후 3:12").
  private static func isWholeTime(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespaces)
      .wholeMatch(of: #/(?:오전|오후|AM|PM|am|pm)?\s?\d{1,2}:\d{2}(?:\s?(?:AM|PM|am|pm))?/#) != nil
  }

  /// 본문 줄: 끝 쪽에 금액 토큰이 있는 줄(토큰 뒤에 글자가 없다), 날짜·시각이 있는 줄, 금액·끊는 말·취소 라벨로 시작하는 줄,
  /// 품목 머리 줄(품명·수량·금액 같은 낱말이 둘 이상). 가게 이름은 이 줄들보다 위에 있다고 본다.
  /// "365 by Whole Foods" 처럼 숫자로 시작하는 가게 이름은 토큰 뒤에 글자가 있어 본문 줄이 아니다.
  private static func isBodyLine(_ line: Line, context: CurrencyContext) -> Bool {
    let characters = self.masked(line.text)
    let hasTrailingAmount = self.amountTokens(in: characters, hasHangul: context.hasHangul).contains { token in
      !characters[token.range.upperBound...].contains(where: \.isLetter)
    }
    return hasTrailingAmount || self.containsDateOrTime(line.text)
      || self.lineLabel(
        self.allAmountLabels + self.cutWords + self.cancelStatusLabels + self.cancelHeaderLabels
          + self.latinCancelHeaderLabels,
        in: line.text
      ) != nil
      || self.words(line.text).count { self.itemHeaderWords.contains(self.normalizedWord($0)) } >= 2
      || self.isLine(self.lineKey(line.text), joinedFrom: [], fragments: self.itemHeaderWords)
  }

  /// 위쪽 줄에서 가게가 아닌 줄: 머리글·문장·버튼, 인사 줄(첫 낱말 Thank·Merci 등), 번호 줄, 주소, 웹·메일, 머리말 줄.
  private static func isSkippedUpperLine(_ text: String) -> Bool {
    let lowercased = text.lowercased()
    let isWeb = ["www.", "http", ".com", ".co.kr", ".kr", "@"].contains { lowercased.contains($0) }
    let isGreeting = self.words(text).first.map { self.greetingWords.contains(self.normalizedWord($0)) } ?? false
    return self.isHeaderSentenceOrButton(text) || isGreeting || self.isNumberLine(text) || self.isAddress(text) || isWeb
      || self.isHeadWordLine(text)
  }

  /// 머리말 줄: 금액·끊는 말·가게·취소·상태 라벨(줄 라벨)로 시작하거나, 첫 낱말이 머리말(줄 머리 낱말)이다.
  private static func isHeadWordLine(_ text: String) -> Bool {
    let labels = self.allAmountLabels + self.cutWords + self.storeLabels + self.shortStoreLabels + self
      .cancelStatusLabels
      + self.cancelHeaderLabels + self.latinCancelHeaderLabels
    // 취소 상태 라벨·머리말 줄은 취소 판정과 같이 붙은 값도 머리말로 본다("거래구분신용취소", "取引区分取消").
    if self.lineLabel(labels, in: text) != nil
      || self
      .lineLabel(self.attachedCancelStatusLabels + self.cancelHeaderLabels, in: text, acceptsAttached: true) != nil
    {
      return true
    }
    let words = self.words(text)
    guard let first = words.first.map({ String($0.lowercased().drop { "*[(【#".contains($0) }) }) else {
      return false
    }
    // 3자 이상 한글·한자·가나 머리말은 시작만으로("대표자홍길동"), 2자 등은 같거나 바로 뒤가 숫자·기호일 때만("대표떡볶이"·"レジャー" 는 아니다).
    let isKorean = self.prefixHeadWords.contains { first.hasPrefix($0) } || self.boundedHeadWords.contains { word in
      first == word || first.hasPrefix(word) && first.dropFirst(word.count).first
        .map { $0.isNumber || ":：-#".contains($0) } == true
    }
    let next = words.dropFirst().first?.first
    let isEnglish = self.englishHeadWords.contains { word in
      first == word && next.map { $0.isNumber || "(#".contains($0) } == true
        || first.hasPrefix(word) && first.dropFirst(word.count).first.map { ":#.".contains($0) } == true
    }
    // 카드 전표 항목("Card Type: VISA", "Auth Code 123456")은 줄에 `:`·`*` 나 숫자 3자 이상이 있을 때만 머리말이다.
    let isCardSlip = self.cardSlipHeadWords.contains(self.normalizedWord(first))
      && (text.contains(where: { ":*".contains($0) }) || text.count(where: \.isNumber) >= 3)
    return isKorean || isEnglish || isCardSlip
  }

  /// 주소: 한국 주소(시·도), "주소" 머리말, 숫자 뒤가 경계인 도로명·동·리·가 번지, 구·군 낱말과 로·길·동 낱말이 함께 있음,
  /// 미국식(숫자로 시작하고 거리 낱말, 주·우편번호), `〒`. "종로3가점"·"강남대로1호점" 은 숫자 뒤가 경계가 아니라 가게다.
  private static func isAddress(_ text: String) -> Bool {
    if text.contains(where: \.isHangul), !CaptureInfoExtractor.koreanAddresses(in: text).isEmpty {
      return true
    }
    let words = self.words(text)
    if let first = words.first, first == "주소" || first.hasPrefix("주소")
      && first.dropFirst(2).first.map({ $0.isNumber || ":：-#".contains($0) }) == true
    {
      return true
    }
    for match in text.matches(of: #/[가-힣0-9]+(?:로|길|동|리|가)\s?\d+/#) {
      let after = text[match.range.upperBound...]
      if after.first.map({ $0.isWhitespace || "-,(".contains($0) }) ?? true || after.hasPrefix("번지")
        || after.hasPrefix("번길")
      {
        return true
      }
    }
    let hasDistrict = words.contains { $0.count >= 2 && ($0.hasSuffix("구") || $0.hasSuffix("군")) }
    let hasRoad = words.contains { $0.count >= 2 && ($0.hasSuffix("로") || $0.hasSuffix("길") || $0.hasSuffix("동")) }
    if hasDistrict, hasRoad {
      return true
    }
    let isStreet = text.prefixMatch(of: #/\d+\s/#) != nil
      && words.contains { self.streetWords.contains(self.normalizedWord($0)) }
    return isStreet || text.contains(#/\b[A-Z]{2}\s\d{5}(?:-\d{4})?\b/#) || text.contains("〒")
      || self.isJapaneseOrChineseAddress(text) || self.isEuropeanAddress(text)
  }

  /// 유럽 주소: 숫자가 있는 줄의 거리 낱말(독일어·네덜란드어 합성어는 낱말 끝 "Hauptstraße 12", 그 밖은 낱말 같음 "12 rue de Rivoli"),
  /// 또는 우편번호 줄(라틴 글자 지명 "10115 Berlin"·"75002 Paris", 네덜란드 "1012 AB"). "Via Roma Pizza"(숫자 없음)·
  /// "2580 ローソン渋谷"(라틴 지명 아님)는 주소가 아니다.
  private static func isEuropeanAddress(_ text: String) -> Bool {
    let words = self.words(text).map { $0.lowercased().precomposedStringWithCanonicalMapping }
    let hasStreet = words.contains { word in
      self.europeanStreetSuffixes.contains(where: word.hasSuffix)
        || self.europeanStreetWords.contains(self.normalizedWord(word))
    }
    return hasStreet && text.contains(where: \.isNumber)
      || text.prefixMatch(of: #/\d{4,5}\s[A-Za-zÀ-ÿ]/#) != nil || text.prefixMatch(of: #/\d{4}\s?[A-Z]{2}\b/#) != nil
  }

  /// 한자 주소: 都道府県省·市 뒤로 区町村郡县 가 오고 숫자·丁目·番地·号 가 있다("東京都渋谷区道玄坂1-2-3", "北京市朝阳区建国路88号"),
  /// 또는 区町村郡 바로 뒤(같은 낱말)에 번지("1-2"·丁目·番地)가 온다("渋谷区道玄坂1-2-3"). "渋谷区役所前店"·"札幌市中央区店" 은 가게다.
  private static func isJapaneseOrChineseAddress(_ text: String) -> Bool {
    let hasAreas = text.contains(#/[都道府県省市].*[区町村郡县]/#)
      && (text.contains(where: \.isNumber) || ["丁目", "番地", "号"].contains(where: text.contains))
    return hasAreas || text.contains(#/[区町村郡]\S*?(?:\d+-\d+|丁目|番地)/#)
  }

  /// 앞뒤 공백·구분 기호(`:：-|`)와 짝이 맞지 않는 끝 괄호를 뺀 값. 줄 전체를 감싼 괄호("(고객용)")는 양쪽을 뺀다.
  /// 짝이 맞는 앞 괄호("(주)예시상사")는 남긴다. 비었으면 nil.
  static func cleanedValue(_ text: some StringProtocol) -> String? {
    let pairs: [Character: Character] = ["(": ")", "[": "]", "【": "】", "（": "）", "<": ">"]
    let closings = Set(pairs.values)
    var value = Substring(text)
    while true {
      value = value.trimmingPrefix { $0.isWhitespace || ":：-|".contains($0) }
      while let last = value.last, last.isWhitespace || ":：-|".contains(last) {
        value = value.dropLast()
      }
      guard let first = value.first, let last = value.last else { return nil }
      let body = value.dropFirst()
      if closings.contains(first) || pairs[first].map({ !body.contains($0) }) == true {
        value = body
      } else if pairs[last] != nil
        || pairs.first(where: { $0.value == last }).map({ !value.dropLast().contains($0.key) }) == true
      {
        value = value.dropLast()
      } else if let closing = pairs[first], body.firstIndex(of: closing) == value.index(before: value.endIndex) {
        value = body.dropLast()
      } else {
        break
      }
    }
    return String(value)
  }
}
