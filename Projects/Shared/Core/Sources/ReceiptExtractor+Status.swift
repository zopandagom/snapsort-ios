import Foundation

// 취소 상태 값과 환불 금액 뒤 말의 대기·부정 판정 (docs/ARCHITECTURE.md §4 영수증 추출).
// 진행·요청·대기·거절·미완료·부정 꼴은 아직(또는 끝내) 취소되지 않은 것이라 근거가 아니다.
extension ReceiptExtractor {
  /// 취소 상태 값: 한글·한자·가나가 든 값은 공백 없이 10자 이하에서 취소 낱말을 부분 문자열로, 라틴 값은 3낱말 이하에서 낱말 같음으로
  /// 본다("Cancellable"·"RETURNABLE" 은 아니다). 대기·부정 말이 있으면(`isPendingCJK`, 같은 구절의 라틴 대기·부정) 아니다.
  static func isCancelStatusValue(_ value: String) -> Bool {
    if self.isCJK(value) {
      let key = self.lineKey(value)
      return key.count <= self.maximumCancelValueLength && !self.cancelRanges(in: key).isEmpty && !self
        .isPendingCJK(key) && !self.isReversalCJK(key)
    }
    let phrases = self.phrases(value)
    guard phrases.joined().count <= self.maximumLatinCancelValueWords else { return false }
    // 대기·거절 말은 값 전체에서, 부정 말과 되돌림(환불 뒤 취소)은 같은 구절에서만 본다("Cancelled - no charge" 는 취소).
    guard !phrases.joined().contains(where: self.latinPendingCancelWords.contains),
          !phrases.contains(where: self.isReversalLatin)
    else { return false }
    return phrases.contains { phrase in
      phrase.contains(where: self.latinCancelValueWords.contains) && !self.isPendingLatin(phrase)
    }
  }

  /// 환불 금액(단계 3) 줄에서 값 토큰 뒤 나머지에 대기·부정 말이 있는지("Refund amount 12.00 pending"·"환불금액 9,000 미처리").
  /// 있으면 그 줄은 취소 근거도 금액 후보도 아니다.
  static func hasPendingTail(_ rest: Substring, context: CurrencyContext) -> Bool {
    let characters = self.masked(String(rest))
    guard let token = self.amountTokens(in: characters, hasHangul: context.hasHangul).first else { return false }
    let tail = String(characters[token.range.upperBound...])
    if self.isCJK(tail) {
      return self.isPendingCJK(self.lineKey(tail))
    }
    return self.phrases(tail).contains(where: self.isPendingLatin)
  }

  /// 환불·반품 금액 줄의 값 뒤에 취소 낱말이 있는지(환불을 되돌린 줄: "환불금액 9,000 취소"·"Refund amount 12.00 cancelled").
  static func hasCancelTail(_ rest: Substring, context: CurrencyContext) -> Bool {
    let characters = self.masked(String(rest))
    guard let token = self.amountTokens(in: characters, hasHangul: context.hasHangul).first else { return false }
    let tail = String(characters[token.range.upperBound...])
    if self.isCJK(tail) {
      return self.reversingCancelWordsCJK.contains(where: self.lineKey(tail).contains)
    }
    return self.phrases(tail).joined().contains(where: self.reversingCancelWords.contains)
  }

  /// 환불·반품 낱말 바로 뒤(연결 글자 하나는 있어도)에 취소 낱말이 오는지("환불을취소"·"退货已取消").
  private static func isReversalCJK(_ key: String) -> Bool {
    self.refundWordsCJK.contains { refund in
      key.ranges(of: refund).contains { range in
        var after = key[range.upperBound...]
        if let first = after.first, self.reversalConnectors.contains(first) {
          after = after.dropFirst()
        }
        return self.reversingCancelWordsCJK.contains(where: after.hasPrefix)
          || self.reversingCancelWordsCJK.contains(where: key[range.upperBound...].hasPrefix)
      }
    }
  }

  /// 한 구절에서 환불·반품 낱말 뒤에 취소 낱말이 오는지("Refund cancelled"·"Return reversal").
  private static func isReversalLatin(_ phrase: [String]) -> Bool {
    guard let refund = phrase.firstIndex(where: self.refundWords.contains) else { return false }
    return phrase[(refund + 1)...].contains(where: self.reversingCancelWords.contains)
  }

  /// 한글·한자·가나 값의 대기 판정(공백 없는 키). 두 글자 이상 대기 말은 부분 문자열, 한 글자 말과 취소 낱말 뒤 말은 자리를 본다.
  private static func isPendingCJK(_ key: String) -> Bool {
    let characters = Array(key)
    let cancels = self.cancelRanges(in: key)
    let cancelStarts = Set(cancels.map(\.lowerBound))
    let isBeforeCancel = { (index: Int) in cancelStarts.contains(index + 1) }
    let following = { (index: Int) in String(characters[(index + 1)...]) }
    // 도착·정산이 아직인 것은 같은 값에 완료 표시가 있으면 취소 자체는 끝난 것이다.
    let isSettledArrival = { (index: Int) in
      self.arrivalWords.contains(where: following(index).hasPrefix) && self.hasCompletedMarker(key)
    }
    if self.pendingCancelWords.contains(where: key.contains) || self.negationForms.contains(where: key.contains) {
      return true
    }
    // "취소후환불"·"취소후" 처럼 바로 앞이 취소 낱말인 후 는 "취소한 뒤" 라 대기가 아니다.
    let isAfterCancel = { (index: Int) in characters[index] == "후" && cancels.contains { $0.upperBound == index } }
    if let last = characters.last, self.pendingCancelSuffixes.contains(last), !isAfterCancel(characters.count - 1) {
      return true
    }
    if cancels.contains(where: { cancel in
      self.pendingAfterCancelWords.contains { String(characters[cancel.upperBound...]).hasPrefix($0) }
    }) {
      return true
    }
    return characters.indices.contains { index in
      let character = characters[index]
      if self.pendingCancelConditions.contains(character) || self.pendingNegationMarkers.contains(character) {
        return isBeforeCancel(index) && !isAfterCancel(index)
      }
      if character == self.waitingMarker {
        let isCompound = self.waitingExceptions.contains { word in
          (max(0, index - word.count + 1) ... index).contains { start in
            start + word.count <= characters.count && String(characters[start ..< start + word.count]) == word
          }
        }
        return !isCompound && !isSettledArrival(index)
      }
      // 未·没·미 는 바로 뒤가 취소 낱말이나 완료·처리 꼴일 때만. "이미" 의 미는 대기가 아니다.
      if self.pendingNotYetMarkers.contains(character),
         !(character == "미" && index > 0 && characters[index - 1] == "이")
      {
        let isBeforeCompletion = isBeforeCancel(index) || self.completionWords
          .contains(where: following(index).hasPrefix)
        return isBeforeCompletion && !isSettledArrival(index)
      }
      return false
    }
  }

  /// 앞에 未·没·미·待 가 붙지 않은 완료 표시가 있는지.
  private static func hasCompletedMarker(_ key: String) -> Bool {
    let blockers: Set<Character> = self.pendingNotYetMarkers.union([self.waitingMarker])
    return self.completedMarkers.contains { marker in
      key.ranges(of: marker).contains { range in
        range.lowerBound == key.startIndex || !blockers.contains(key[key.index(before: range.lowerBound)])
      }
    }
  }

  /// 라틴 구절(정규화한 낱말)의 대기·부정. 번호 표시(no·nr·n° 가 "." 으로 끝나거나 다음이 숫자)는 부정이 아니다.
  private static func isPendingLatin(_ phrase: [String]) -> Bool {
    phrase.contains(where: self.latinPendingCancelWords.contains) || phrase.indices.contains { index in
      self.latinNegationWords.contains(phrase[index]) && !self.isNumberMarker(at: index, in: phrase)
    }
  }

  private static func isNumberMarker(at index: Int, in phrase: [String]) -> Bool {
    // `phrases` 가 "No." 의 끝 "." 을 남겨 둔다.
    let word = phrase[index]
    guard ["no", "nr", "n°", "no.", "nr.", "n°."].contains(word) else { return false }
    return word.hasSuffix(".") || (index + 1 < phrase.count && phrase[index + 1].first?.isNumber == true)
  }

  /// 라틴 값을 구절(`-`·`–`·`,`·`;`·`/` 로 나눈 조각)로 나누고 낱말을 정규화한다. 번호 표시 판정을 위해 "No." 의 끝 "." 은 남긴다.
  private static func phrases(_ value: String) -> [[String]] {
    value.split(whereSeparator: { "-–,;/".contains($0) }).map { phrase in
      self.words(phrase).map { word in
        let normalized = self.normalizedWord(word)
        return word.hasSuffix(".") && ["no", "nr", "n°"].contains(normalized) ? normalized + "." : normalized
      }.filter { !$0.isEmpty }
    }.filter { !$0.isEmpty }
  }

  /// 키에서 취소 값 낱말이 나오는 자리(문자 위치).
  private static func cancelRanges(in key: String) -> [Range<Int>] {
    self.cancelValueWords.flatMap { word in
      key.ranges(of: word).map { range in
        let start = key.distance(from: key.startIndex, to: range.lowerBound)
        return start ..< start + word.count
      }
    }
  }
}
