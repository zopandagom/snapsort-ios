import CoreGraphics
import Foundation

/// 영수증 이미지의 OCR 줄에서 가게·금액·통화·취소를 찾는 규칙 (docs/ARCHITECTURE.md §4 영수증 추출).
/// 원칙은 "틀린 값보다 빈 값"이다: 고를 근거가 둘 이상으로 갈리거나 줄의 뜻이 불분명하면 금액 모름·가게 모름으로 둔다.
/// 표의 낱말은 앞부분·부분 문자열로 대조하지 않고 네 방식(줄 라벨·낱말 같음·줄 같음·줄 머리 낱말) 중 하나로 대조한다.
/// 금액(라벨 줄 → 이웃 줄 → 단계별 고르기) → 취소 → 가게 순서로 찾는다. 언어 모델 보강은 없다.
/// 라벨은 `ClassificationRules` 키워드 표·기프티콘 라벨 표와 따로 둔다(`scripts/mask-samples.py` 는 키워드 표만 읽는다).
/// 결과에 사진에서 읽은 텍스트(가게·금액)가 들어 있으므로 로그에 남기지 않는다 (docs/CONVENTIONS.md §4).
public enum ReceiptExtractor {
  /// 추출 규칙 버전. 규칙을 바꿔 같은 줄에서 다른 값이 나올 수 있으면 올린다.
  /// 저장소가 이 버전으로 추출하지 않은 행을 다시 추출 대상으로 돌려준다.
  public static let rulesVersion = 1

  /// 영수증으로 분류한 이미지의 OCR 줄에서 가게·금액·통화·취소를 찾는다. 날짜를 쓰지 않아 달력·기준일을 받지 않는다.
  public static func extract(from textLines: [RecognizedTextLine]) -> ReceiptInfo {
    let lines = textLines.map(Line.init)
    let context = CurrencyContext(texts: lines.map(\.text))
    let labeled = lines.indices.compactMap { self.labeledAmount(at: $0, in: lines, context: context) }
    let chosen = self.chosenAmount(from: labeled)
    let isCancelled = chosen?.token.isNegative == true
      || labeled.contains { $0.stage == 3 && $0.token.isPositive }
      || self.hasCancelTitleOrStatus(in: lines, context: context)
    return ReceiptInfo(
      storeName: self.storeName(in: lines, context: context),
      amount: chosen.flatMap { value in value.currency.flatMap { value.token.amount(in: $0) } },
      isCancelled: isCancelled
    )
  }

  /// 가게별 묶음 키: 소문자, 공백 제거, 법인 표기 제거, 글자·숫자만 남긴다. 지점 이름은 남긴다. 글자·숫자가 남지 않으면 nil.
  /// 공백을 먼저 지워 "Co., Ltd." 처럼 띄어 쓴 법인 표기도 지우고, 법인 표기는 맨 앞·맨 끝에서만 지운다("Zinc.Cafe" 는 그대로).
  public static func storeKey(_ storeName: String) -> String? {
    var name = Substring(storeName.lowercased().filter { !$0.isWhitespace })
    while let mark = self.corporateMarks.first(where: { name.hasPrefix($0) || name.hasSuffix($0) }) {
      name = name.hasPrefix(mark) ? name.dropFirst(mark.count) : name.dropLast(mark.count)
    }
    let key = String(name.filter { $0.isLetter || $0.isNumber })
    return key.isEmpty ? nil : key
  }

  /// 묶음 키에서 지우는 법인 표기. 소문자·공백 없이 적고 긴 것부터 지운다("co.,ltd." 를 "ltd." 보다 먼저).
  static let corporateMarks = [
    "co.,ltd.", "co.,ltd", "주식회사", "유한회사", "株式会社", "(주)", "(유)", "(株)", "ltd.", "inc.", "corp.", "㈜", "㈱",
  ]

  /// 검사에 쓰는 줄. 원문은 그대로 두고 연속 점·말줄임·가운뎃점(점 리더 "TOTAL.......45.20")을 공백 하나로 바꾼 사본을 쓴다.
  struct Line {
    let text: String
    let original: String
    let box: CGRect

    init(_ line: RecognizedTextLine) {
      self.original = line.text
      self.text = line.text.replacing(#/[.…·]{2,}/#, with: " ")
      self.box = line.boundingBox
    }
  }
}

// 표·대조 방식·금액·취소. 진입점과 줄은 위 본문에 둔다.
extension ReceiptExtractor {
  // MARK: - 표

  /// 금액 라벨. 단계 1(최종 결제) → 2(합계) → 3(취소 전표, 취소 판정에 쓰고 1·2 값이 없을 때만 금액). 공백 없이 소문자로 적는다.
  static let amountLabels: [Int: [String]] = [
    1: [
      "결제금액", "총결제금액", "최종결제금액", "실결제금액", "결제하실금액", "승인금액", "받을금액", "청구금액", "grandtotal", "totaldue",
      "amountdue", "totalamountdue", "totalamount", "totalpaid", "お会計", "ご請求額", "お支払金額", "お支払い金額", "お支払合計",
      "ご利用金額", "ご利用額",
    ],
    2: [
      "합계금액", "합계액", "총합계금액", "총합계", "총금액", "총액", "합계", "total", "合計金額", "税込合計", "合計", "合计", "総合計",
      "総合計金額", "総額",
    ],
    3: ["취소금액", "환불금액", "반품금액"],
  ]
  static let allAmountLabels = amountLabels.values.flatMap(\.self)
  /// 라벨 바로 뒤에서 건너뛰는 꼬리 말(낱말 같음): "合計 金額 ¥1,234", "TOTAL AMOUNT DUE 45.20".
  static let labelTailWords: Set<String> = ["금액", "액", "金額", "額", "amount", "due", "payable", "paid", "sale"]
  /// 통화 표시 낱말(낱말 같음).
  static let currencyWords: Set<String> = ["krw", "usd", "eur", "jpy", "cny", "rmb", "원", "円", "元", "won"]
  /// 금액 값 범위를 끊는 말(낱말 같음, 또는 바로 뒤가 숫자·`:`·`：`·`=`·통화 기호).
  static let cutWords = [
    "부가세", "부가가치세", "공급가액", "공급가", "과세", "면세", "비과세", "할인", "받은금액", "받은돈", "거스름", "잔돈", "승인번호", "카드번호",
    "포인트", "적립", "잔액", "수량", "subtotal", "tax", "vat", "change", "cash", "tip", "qty", "savings", "discount", "お預り",
    "お釣り", "小計", "税",
  ]
  /// 취소 전표 이름(줄 같음, 위치 무관).
  static let cancelTitles: Set<String> = [
    "승인취소", "취소승인", "신용취소", "신용승인취소", "카드승인취소", "승인취소전표", "취소전표", "취소영수증", "취소매출전표", "매출전표취소",
    "매출취소", "매출취소전표", "거래취소", "거래취소전표", "현금영수증취소", "현금취소", "취소거래", "반품영수증", "환불영수증", "refundreceipt",
  ]
  /// 취소 상태 문구(줄 같음, 첫 금액 줄보다 위에서만).
  static let cancelStatusPhrases: Set<String> = [
    "취소완료", "결제취소완료", "주문취소완료", "환불완료", "반품완료", "결제가취소되었습니다", "취소되었습니다", "환불되었습니다",
    "결제취소되었습니다", "void", "voided", "refunded", "cancelled", "canceled", "cancellation",
  ]
  /// 취소 상태 라벨(줄 라벨). 값에 `cancelValueWords` 가 있고 `pendingCancelWords` 가 없으면 취소다.
  static let cancelStatusLabels = [
    "거래종류", "거래구분", "거래유형", "결제구분", "결제상태", "거래상태", "주문상태", "처리상태", "구분", "상태", "transactiontype", "type",
    "status",
  ]
  static let cancelValueWords = ["취소", "환불", "반품", "void", "refund", "cancel"]
  static let pendingCancelWords = [
    "가능", "불가", "신청", "요청", "접수", "안내", "정책", "방법", "기한", "수수료", "possible", "available", "eligible", "request",
    "policy",
  ]
  /// 값과 무관하게 취소 근거인 머리말(줄 라벨).
  static let cancelHeaderLabels = ["취소일시", "취소일자", "취소승인번호", "원거래일자", "원승인번호", "원거래승인번호"]

  // MARK: - 대조 방식

  /// 줄 라벨 바로 뒤 경계로 받는 글자(공백·숫자 밖).
  private static let labelBoundaries: Set<Character> = [
    ":", "：", "]", ")", "|", "-", "(", "（", "[", "【", "】", "）", "−", "+", "₩", "￦", "$", "€", "¥", "￥",
  ]

  /// 줄 라벨: 줄 맨 앞(앞쪽 기호는 건너뛴다)의 라벨과 그 뒤 원래 텍스트. 긴 라벨부터 대조하고, 라벨 바로 뒤가 경계여야 한다
  /// (`acceptsAttached` 면 경계 없이 붙은 값도 받는다). "Totally"·"상호저축은행" 은 라벨이 아니다.
  static func lineLabel(
    _ labels: [String],
    in text: String,
    acceptsAttached: Bool = false
  ) -> (label: String, rest: Substring)? {
    for label in labels.sorted(by: { $0.count > $1.count }) {
      guard let rest = GifticonExtractor.text(after: label, in: text) else { continue }
      if acceptsAttached || rest.first
        .map({ $0.isWhitespace || $0.isNumber || self.labelBoundaries.contains($0) }) ?? true
      {
        return (label, rest)
      }
    }
    return nil
  }

  /// 낱말 같음에 쓰는 낱말: 소문자, 앞뒤 기호(`[]()<>【】（）*#`)와 끝 문장 부호(`.`·`:`·`,`)를 뺀다.
  static func normalizedWord(_ word: some StringProtocol) -> String {
    let symbols = CharacterSet(charactersIn: "[]()<>【】（）*#")
    return word.lowercased().trimmingCharacters(in: symbols)
      .trimmingCharacters(in: CharacterSet(charactersIn: ".:,"))
      .trimmingCharacters(in: symbols)
  }

  static func words(_ text: some StringProtocol) -> [Substring] {
    text.split(whereSeparator: \.isWhitespace).map { Substring($0) }
  }

  /// 줄 같음에 쓰는 키: 공백 없이 소문자로, 기호(`[]()<>【】（）*#=-`)는 어디 있든 빼고 끝 문장 부호를 뺀다.
  static func lineKey(_ text: some StringProtocol) -> String {
    let removed = Set("[]()<>【】（）*#=-")
    return String(text.lowercased().filter { !$0.isWhitespace && !removed.contains($0) })
      .trimmingCharacters(in: CharacterSet(charactersIn: ".:,!"))
  }

  /// 줄 같음: 키가 `words`·`fragments` 의 낱말을 이어 붙인 것과 같고, `words` 의 낱말이 하나 이상 들었거나 조각 낱말이 둘 이상이다.
  static func isLine(_ key: String, joinedFrom words: Set<String>, fragments: Set<String> = []) -> Bool {
    let characters = Array(key)
    guard !characters.isEmpty else { return false }
    // 위치마다 그 위치까지 이어 붙일 수 있는 (낱말이 들었는지, 조각 수(2 이상은 2)) 상태.
    var states: [Set<Int>] = Array(repeating: [], count: characters.count + 1)
    states[0] = [0]
    for start in characters.indices where !states[start].isEmpty {
      for end in start + 1 ... characters.count {
        let piece = String(characters[start ..< end])
        let isWord = words.contains(piece)
        guard isWord || fragments.contains(piece) else { continue }
        for state in states[start] {
          let hasWord = state >= 3 || isWord
          let fragmentCount = min(2, state % 3 + (isWord ? 0 : 1))
          states[end].insert((hasWord ? 3 : 0) + fragmentCount)
        }
      }
    }
    return states[characters.count].contains { $0 >= 3 || $0 == 2 }
  }

  // MARK: - 금액

  /// 값을 찾은 금액 라벨 줄(또는 이웃 줄 값). 통화는 고른 뒤 쓴다.
  struct LabeledAmount {
    let stage: Int
    let token: AmountToken
    let currency: ReceiptCurrency?
  }

  /// 줄 맨 앞이 금액 라벨이고 라벨 줄 판정을 통과하면 그 값. 범위에 토큰이 없으면 이웃 줄을 본다.
  private static func labeledAmount(at index: Int, in lines: [Line], context: CurrencyContext) -> LabeledAmount? {
    let line = lines[index]
    guard let (label, rest) = self.lineLabel(self.allAmountLabels, in: line.text),
          let stage = self.amountLabels.first(where: { $0.value.contains(label) })?.key,
          self.isAmountLabelLine(rest, context: context)
    else { return nil }
    let range = self.valueRange(rest)
    if let token = self.amountTokens(in: self.masked(range), hasHangul: context.hasHangul).last {
      return LabeledAmount(stage: stage, token: token, currency: context.currency(of: token, lineText: String(rest)))
    }
    let leftover = self.words(range).filter { !self.currencyWords.contains(self.normalizedWord($0)) }
    guard !leftover.joined().contains(where: \.isLetter),
          let (neighbor, token) = self.neighborAmount(of: index, in: lines, context: context)
    else { return nil }
    return LabeledAmount(
      stage: stage,
      token: token,
      currency: context.currency(of: token, lineText: String(rest) + " " + lines[neighbor].text)
    )
  }

  /// 라벨 줄 판정: 앞 구분 기호와 숫자 없는 괄호 덧말을 뺀 사본에서 꼬리 말을 건너뛴 첫 낱말이 없거나, 금액 토큰으로 시작하거나,
  /// 통화 표시 낱말이어야 한다. "TOTAL SAVINGS 5.00"·"합계 수량 3"·"결제금액 안내" 는 라벨 줄이 아니다.
  private static func isAmountLabelLine(_ rest: Substring, context: CurrencyContext) -> Bool {
    var judged = self.removingParentheticals(rest).drop(while: \.isWhitespace)
    if let first = judged.first,
       ":：|".contains(first) || first == "-" && judged.dropFirst().first?.isWhitespace != false
    {
      judged = judged.dropFirst()
    }
    guard let next = self.words(judged).first(where: { !self.labelTailWords.contains(self.normalizedWord($0)) }) else {
      return true
    }
    if let first = next.first, first.isNumber || "-−(₩￦$€¥￥\\".contains(first) {
      return true
    }
    return self.currencyWords.contains(self.normalizedWord(next))
      || !self.amountTokens(in: Array(next), hasHangul: context.hasHangul).isEmpty
  }

  /// 값 범위: 숫자 없는 괄호 덧말을 지우고, 처음 나오는 끊는 말 앞까지.
  private static func valueRange(_ rest: Substring) -> String {
    let text = self.removingParentheticals(rest)
    var end = text.endIndex
    for word in self.words(text) where self.isCutWord(word) {
      end = word.startIndex
      break
    }
    return String(text[..<end])
  }

  /// 끊는 말: 낱말이 같거나, 끊는 말 바로 뒤가 숫자·`:`·`：`·`=`·통화 기호다("부가세818", "VAT:818", "TAX=3.20").
  private static func isCutWord(_ word: Substring) -> Bool {
    let normalized = self.normalizedWord(word)
    let lowercased = String(word.lowercased().drop { "[(【（*#".contains($0) })
    return self.cutWords.contains { cut in
      normalized == cut || lowercased.hasPrefix(cut) && lowercased.dropFirst(cut.count).first
        .map { $0.isNumber || ":：=₩￦$€¥￥".contains($0) } == true
    }
  }

  /// 숫자가 없는 괄호 덧말("(VAT포함)"·"(원)"·"(税込)")을 공백으로 바꾼다. 숫자가 든 괄호("(9,000)")는 남긴다.
  static func removingParentheticals(_ text: some StringProtocol) -> String {
    String(text).replacing(#/[(（\[【][^()（）\[\]【】0-9]*[)）\]】]/#, with: " ")
  }

  /// 범위에 토큰이 없을 때 이웃 줄의 금액: 같은 높이 오른쪽 줄 중 줄 전체가 금액 토큰 하나인 가장 오른쪽 줄(그보다 오른쪽에 다른
  /// 줄이 있으면 열을 믿을 수 없어 없음), 같은 높이 후보가 없을 때만 바로 아래 줄(그 줄과 같은 높이에 다른 금액 줄이 없을 때만).
  private static func neighborAmount(
    of index: Int,
    in lines: [Line],
    context: CurrencyContext
  ) -> (Int, AmountToken)? {
    let box = lines[index].box
    let others = lines.indices.filter { $0 != index && !self.startsWithReceiptLabel(lines[$0].text) }
    let single = { (other: Int) in self.singleToken(in: lines[other].text, context: context) }
    let sameRow = others.filter {
      abs(lines[$0].box.midY - box.midY) < box.height / 2 && lines[$0].box.minX >= box.midX
    }
    if !sameRow.isEmpty {
      guard let best = sameRow.filter({ single($0) != nil }).max(by: { lines[$0].box.maxX < lines[$1].box.maxX }),
            let token = single(best),
            !sameRow.contains(where: { single($0) == nil && lines[$0].box.maxX > lines[best].box.maxX })
      else { return nil }
      return (best, token)
    }
    guard let below = others.filter({
      let other = lines[$0].box
      return other.minY >= box.midY && other.minY - box.maxY <= box.height * GifticonExtractor.maximumLineGapRatio
        && other.maxX > box.minX && other.minX < box.maxX
    }).min(by: { lines[$0].box.minY < lines[$1].box.minY }),
      let token = single(below)
    else { return nil }
    let belowBox = lines[below].box
    let hasOtherColumn = others.contains {
      $0 != below && abs(lines[$0].box.midY - belowBox.midY) < belowBox.height / 2 && single($0) != nil
    }
    return hasOtherColumn ? nil : (below, token)
  }

  /// 줄 전체가 금액 토큰 하나(앞뒤 공백·통화 표시 낱말만)면 그 토큰.
  private static func singleToken(in text: String, context: CurrencyContext) -> AmountToken? {
    var characters = self.masked(text)
    let tokens = self.amountTokens(in: characters, hasHangul: context.hasHangul)
    guard tokens.count == 1, let token = tokens.first else { return nil }
    characters.replaceSubrange(token.range, with: [" "])
    let rest = self.words(String(characters))
    return rest.allSatisfy { self.currencyWords.contains(self.normalizedWord($0)) } ? token : nil
  }

  /// 영수증 라벨(금액·가게·취소)로 시작하는 줄. 이웃 줄 값으로 고르지 않는다.
  static func startsWithReceiptLabel(_ text: String) -> Bool {
    self.lineLabel(
      self.allAmountLabels + self.storeLabels + self.shortStoreLabels + self.cancelStatusLabels + self
        .cancelHeaderLabels,
      in: text
    ) != nil
  }

  /// 값이 있는 라벨 줄 중 가장 높은 단계(1·2, 없으면 3)의 값. 그 단계의 값(수·통화)이 모두 같으면 그 값, 다르면 금액 모름(nil).
  private static func chosenAmount(from labeled: [LabeledAmount]) -> (token: AmountToken, currency: ReceiptCurrency?)? {
    guard let stage = labeled.filter({ $0.stage < 3 }).map(\.stage).min() ?? labeled.map(\.stage).min() else {
      return nil
    }
    let candidates = labeled.filter { $0.stage == stage }
    let distinct = Set(candidates.map { "\($0.token.numberKey)|\($0.currency?.rawValue ?? "?")" })
    guard distinct.count == 1, let first = candidates.first else { return nil }
    // 같은 값 중 하나라도 음수면 그것을 고른다(취소 근거).
    return (candidates.first { $0.token.isNegative }?.token ?? first.token, first.currency)
  }

  // MARK: - 취소

  /// 취소 전표 이름 줄(위치 무관), 첫 금액 줄보다 위의 상태 문구 줄, 취소 상태 줄·취소 머리말 줄이 있는지.
  private static func hasCancelTitleOrStatus(in lines: [Line], context: CurrencyContext) -> Bool {
    let ordered = lines.sorted { ($0.box.minY, $0.box.minX) < ($1.box.minY, $1.box.minX) }
    let firstAmount = ordered.firstIndex {
      !self.amountTokens(in: self.masked($0.text), hasHangul: context.hasHangul).isEmpty
    } ?? ordered.count
    for (position, line) in ordered.enumerated() {
      let key = self.lineKey(line.text)
      if self.isLine(key, joinedFrom: self.cancelTitles)
        || position < firstAmount && self.isLine(key, joinedFrom: self.cancelStatusPhrases)
        || self.lineLabel(self.cancelHeaderLabels, in: line.text) != nil
      {
        return true
      }
      if let (_, rest) = self.lineLabel(self.cancelStatusLabels, in: line.text),
         let value = self.cleanedValue(rest).map(self.lineKey),
         self.cancelValueWords.contains(where: value.contains),
         !self.pendingCancelWords.contains(where: value.contains)
      {
        return true
      }
    }
    return false
  }
}
