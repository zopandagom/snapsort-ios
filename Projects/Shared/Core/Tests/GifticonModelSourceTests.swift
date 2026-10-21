import Core
import CoreGraphics
import Foundation
import Testing

/// 추출 값의 필드별 출처: `filling` 이 모델로 채운 필드 표시, 출처 없이 마친 옛 행의 출처 판정.
/// 테스트의 OCR 줄과 모델 답은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
struct GifticonModelSourceTests {
  @Test("모델로 채운 필드만 출처에 넣는다(두 필드 모두)")
  func marksBothModelFilledFields() {
    let lines = [line("스타벅스", y: 0.2), line("Valid until 2026.12.31", y: 0.5)]
    let rules = extract(lines)

    let filled = fill(rules, GifticonModelAnswer(expiryText: "2026.12.31", redemptionPlace: "스타벅스"), lines)

    #expect(rules.modelFilledFields.isEmpty)
    #expect(filled == GifticonInfo(
      expiryDate: day(2026, 12, 31),
      redemptionPlace: "스타벅스",
      modelFilledFields: [.expiryDate, .redemptionPlace]
    ))
  }

  @Test("규칙이 찾은 필드는 출처에 넣지 않는다")
  func doesNotMarkRuleFields() {
    let lines = [line("스타벅스", y: 0.2), line("유효기간 2026.12.31", y: 0.5)]
    let rules = extract(lines)

    let filled = fill(rules, GifticonModelAnswer(expiryText: "2026.12.31", redemptionPlace: "스타벅스"), lines)

    #expect(rules.expiryDate == day(2026, 12, 31))
    #expect(filled.redemptionPlace == "스타벅스")
    #expect(filled.modelFilledFields == [.redemptionPlace])
  }

  @Test("확인하지 못해 버린 답은 출처에 넣지 않는다")
  func doesNotMarkRejectedAnswer() {
    let lines = [line("STARBUCKS", y: 0.2), line("Valid until 2026.12.31", y: 0.5)]

    let filled = fill(
      extract(lines),
      GifticonModelAnswer(expiryText: "2030.01.01", redemptionPlace: "투썸플레이스"),
      lines
    )

    #expect(filled == GifticonInfo(expiryDate: nil, redemptionPlace: nil))
    #expect(filled.modelFilledFields.isEmpty)
  }

  @Test("값이 없는 필드는 출처에 담기지 않는다")
  func dropsSourceOfMissingValue() {
    let info = GifticonInfo(expiryDate: nil, redemptionPlace: "CU", modelFilledFields: [.expiryDate, .redemptionPlace])

    #expect(info.modelFilledFields == [.redemptionPlace])
    #expect(GifticonInfo(expiryDate: nil, redemptionPlace: nil, modelFilledFields: Set(GifticonInfo.Field.allCases))
      .modelFilledFields.isEmpty)
  }

  @Test("옛 마침 행의 출처: 값이 있고 다시 계산한 규칙 값과 다른 필드만 모델로 본다", arguments: SourceCase.all)
  func resolvesSourcesAgainstRules(_ sourceCase: SourceCase) {
    #expect(GifticonExtractor.modelFilledFields(stored: sourceCase.stored, rules: sourceCase.rules) == sourceCase
      .expected)
  }
}

/// 출처 판정 한 경우: 저장 값, 다시 계산한 규칙 값, 기대 출처.
struct SourceCase: Sendable, CustomTestStringConvertible {
  let stored: GifticonInfo
  let rules: GifticonInfo
  let expected: Set<GifticonInfo.Field>
  let testDescription: String

  static let all = [
    Self("같으면 규칙", stored: (20_261_231, "스타벅스"), rules: (20_261_231, "스타벅스"), expected: []),
    Self("규칙이 비움", stored: (20_261_231, "스타벅스"), rules: (nil, nil), expected: [.expiryDate, .redemptionPlace]),
    Self("만료일만 다름", stored: (20_261_231, "스타벅스"), rules: (20_261_130, "스타벅스"), expected: [.expiryDate]),
    Self("교환처만 다름", stored: (20_261_231, "투썸"), rules: (20_261_231, "스타벅스"), expected: [.redemptionPlace]),
    Self("저장 값 없음", stored: (nil, nil), rules: (20_261_231, "스타벅스"), expected: []),
    Self("섞임: 교환처만 모델", stored: (nil, "스타벅스"), rules: (20_261_231, nil), expected: [.redemptionPlace]),
    Self("섞임: 만료일만 모델", stored: (20_261_231, nil), rules: (nil, "스타벅스"), expected: [.expiryDate]),
  ]

  /// 만료일은 yyyymmdd 정수.
  init(
    _ description: String,
    stored: (expiry: Int?, place: String?),
    rules: (expiry: Int?, place: String?),
    expected: Set<GifticonInfo.Field>
  ) {
    self.stored = GifticonInfo(expiryDate: stored.expiry.map(Self.day), redemptionPlace: stored.place)
    self.rules = GifticonInfo(expiryDate: rules.expiry.map(Self.day), redemptionPlace: rules.place)
    self.expected = expected
    self.testDescription = description
  }

  private static func day(_ number: Int) -> LocalDate {
    LocalDate(year: number / 10000, month: number / 100 % 100, day: number % 100)!
  }
}

private let calendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
  return calendar
}()

/// 기준일(이미지 생성 시각).
private let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12))!

private func extract(_ lines: [RecognizedTextLine]) -> GifticonInfo {
  GifticonExtractor.extract(from: lines, referenceDate: referenceDate, calendar: calendar)
}

private func fill(_ info: GifticonInfo, _ answer: GifticonModelAnswer, _ lines: [RecognizedTextLine]) -> GifticonInfo {
  GifticonExtractor.filling(info, with: answer, from: lines, referenceDate: referenceDate, calendar: calendar)
}

private func day(_ year: Int, _ month: Int, _ day: Int) -> LocalDate? {
  LocalDate(year: year, month: month, day: day)
}

private func line(_ text: String, y: CGFloat = 0.5) -> RecognizedTextLine {
  RecognizedTextLine(text: text, confidence: 1, boundingBox: CGRect(x: 0.1, y: y, width: 0.8, height: 0.03))
}
