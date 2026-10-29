import CoreGraphics
import Foundation
import Testing
@testable import Core

// GifticonExtractorTests 의 교환처 테스트(라벨 없는 교환처, 라벨 값 거르기). 도우미(`extract`·`line`)는 GifticonExtractorTests.swift 에 있다.
// 테스트의 OCR 줄은 지어낸 텍스트이고 번호는 지어낸 값이다. 실제 기프티콘에서 읽은 텍스트는 넣지 않는다 (docs/CONVENTIONS.md §3).

extension GifticonExtractorTests {
  @Test("라벨이 없으면 줄 전체가 목록 브랜드인 줄을 교환처로 쓴다")
  func readsUnlabeledBrandLine() {
    let info = extract([
      line("상품권", y: 0.1),
      line("emart", y: 0.15),
      line("신세계", y: 0.3),
      line("신세계이마트", y: 0.45),
      line("가나다 신세계 상품권 5만원권", y: 0.5),
      line("유효기간 : 2026.10.01 ~ 2027.03.31", y: 0.6),
      line("1234 - 5678 - 9012", y: 0.8),
    ])
    // "신세계" 는 "신세계이마트" 에 포함돼 빠지고, "emart" 와 "신세계이마트" 는 같은 교환처라 긴 이름을 쓴다.
    #expect(info.redemptionPlace == "신세계이마트")
    #expect(info.expiryDate == LocalDate(year: 2027, month: 3, day: 31))
  }

  @Test("상품명 앞 괄호 브랜드를 교환처로 쓴다")
  func readsBracketBrand() {
    let withLine = extract([
      line("123456789012 코드번호 복사", y: 0.2),
      line("스타벅스", y: 0.3),
      line("[스타벅스] 아이스 라떼 T", y: 0.35),
      line("2026.11.30까지", y: 0.4),
      line("- 스타벅스 카드에 잔액이 충전됩니다.", y: 0.6),
    ])
    #expect(withLine.redemptionPlace == "스타벅스")
    #expect(extract([line("【 Starbucks 】 아이스 라떼 T")]).redemptionPlace == "Starbucks")
    // 목록에 없는 이름은 같은 이름이 줄 전체인 줄이 따로 있을 때만 받는다.
    #expect(extract([line("가나다커피", y: 0.3), line("[가나다커피] 라떼", y: 0.35)]).redemptionPlace == "가나다커피")
  }

  @Test(
    "괄호만으로는 목록에 없는 이름을 교환처로 보지 않는다",
    arguments: ["[단독] 아이스 라떼 T", "[1+1] 아이스 라떼 T", "[가나다커피] 라떼"]
  )
  func ignoresUnconfirmedBracket(_ text: String) {
    #expect(extract([line(text)]).redemptionPlace == nil)
  }

  @Test("안내문 속 브랜드는 교환처로 보지 않는다")
  func ignoresBrandInsideSentence() {
    let info = extract([
      line("- 스타벅스 앱에서도 주문할 수 있습니다.", y: 0.5),
      line("CU 모바일 상품권", y: 0.6),
    ])
    #expect(info.redemptionPlace == nil)
  }

  @Test("서로 다른 교환처 후보가 있으면 비운다")
  func clearsConflictingBrands() {
    #expect(extract([line("CU", y: 0.3), line("GS25", y: 0.4)]).redemptionPlace == nil)
    #expect(extract([line("스타벅스", y: 0.3), line("[투썸] 케이크", y: 0.4)]).redemptionPlace == nil)
    // 이름만 겹치는 다른 교환처는 포함 후보로 빼지 않는다.
    #expect(extract([line("이마트", y: 0.3), line("이마트24", y: 0.4)]).redemptionPlace == nil)
    // 같은 교환처의 짧은 별칭은 뺀다.
    #expect(extract([line("투썸", y: 0.3), line("투썸플레이스", y: 0.4)]).redemptionPlace == "투썸플레이스")
  }

  @Test("교환처 라벨이 있으면 라벨 값만 쓰고 라벨 없는 규칙은 쓰지 않는다")
  func prefersLabel() {
    let labeled = extract([line("스타벅스", y: 0.3), line("교환처 가나다카페", y: 0.5)])
    #expect(labeled.redemptionPlace == "가나다카페")
    // 라벨 값이 로고라 읽은 글자가 없으면 목록 브랜드 줄이 있어도 비운다.
    let logoPlace = extract([line("스타벅스", y: 0.2), line("교환처", y: 0.5), line("유효기간 2026.12.31", y: 0.55)])
    #expect(logoPlace.redemptionPlace == nil)
  }

  @Test(
    "라벨 뒤가 안내문이면 라벨로 보지 않는다",
    arguments: [
      "· 교환처 사정에 따라 상품이 변경될 수 있습니다",
      "교환처 사정에 따라",
      "사용처 상황에 따라 품절될 수 있음",
      "교환처 재고가 없는 경우 다른 상품으로 교환",
    ]
  )
  func ignoresNoticeAfterLabel(_ text: String) {
    #expect(extract([line(text)]).redemptionPlace == nil)
    // 라벨이 아니므로 라벨 없는 규칙이 브랜드 줄을 찾는다.
    #expect(extract([line("스타벅스", y: 0.3), line(text, y: 0.7)]).redemptionPlace == "스타벅스")
  }

  @Test(
    "라벨 값이 다른 항목이면 비운다",
    arguments: [
      "주문번호 1234-5678-9012", "1234-5678-9012", "2026.12.31", "발행일 가나다", "선물하기",
      "가나다라마바사아자차카타파하 가나다라마바사", "전국 매장에서 사용 가능합니다",
    ]
  )
  func ignoresOtherItemBelowLabel(_ text: String) {
    #expect(extract([line("교환처", y: 0.5), line(text, y: 0.55)]).redemptionPlace == nil)
    #expect(extract([line("교환처 \(text)")]).redemptionPlace == nil)
  }

  @Test(
    "라벨 값 뒤 괄호 안내는 라벨을 막지 않고 괄호 앞 값을 쓴다",
    arguments: [
      ("교환처 : 이마트 (매장 사정에 따라 상이할 수 있습니다)", "이마트"),
      ("사용처 : CU (재고가 없는 경우 다른 상품으로 교환)", "CU"),
      ("교환처 : CU (일부 매장 제외)", "CU (일부 매장 제외)"),
    ]
  )
  func readsValueBeforeRemark(text: String, expected: String) {
    #expect(extract([line(text)]).redemptionPlace == expected)
    let valueBelow = String(text.drop { $0 != ":" }.dropFirst())
    #expect(extract([line("교환처", y: 0.5), line(valueBelow, y: 0.55)]).redemptionPlace == expected)
  }

  @Test("라벨 뒤가 괄호 덧말뿐이면 덧말을 교환처로 쓰지 않고 아래 줄 값을 읽는다")
  func readsValueBelowRemarkOnlyLabel() {
    #expect(extract([line("사용처 (일부 매장 제외)", y: 0.5), line("CU", y: 0.55)]).redemptionPlace == "CU")
    #expect(extract([line("사용처 (일부 매장 제외)")]).redemptionPlace == nil)
  }

  @Test("괄호로 시작하는 라벨 값은 덧말이 아니라 같은 줄 값으로 읽는다")
  func readsValueStartingWithParenthesis() {
    #expect(extract([line("교환처 : (주)가나다")]).redemptionPlace == "(주)가나다")
    #expect(extract([line("교환처 (주)가나다", y: 0.5), line("아이스 라떼 T", y: 0.55)]).redemptionPlace == "(주)가나다")
    #expect(extract([line("교환처 (주)가나다 (매장 사정에 따라 상이할 수 있습니다)")]).redemptionPlace == "(주)가나다")
  }

  @Test("괄호 안내만 있는 라벨 줄은 라벨로 보지 않는다")
  func ignoresLabelWithOnlyRemark() {
    #expect(extract([line("교환처 (매장 사정에 따라 다름)")]).redemptionPlace == nil)
    #expect(extract([line("스타벅스", y: 0.3), line("교환처 (매장 사정에 따라 다름)", y: 0.7)]).redemptionPlace == "스타벅스")
  }

  @Test("'다'·'요'로 끝나는 한 낱말 가게 이름은 안내문으로 보지 않는다")
  func keepsSingleWordPlaceEndingInSentenceEnding() {
    #expect(extract([line("교환처 가나다하다")]).redemptionPlace == "가나다하다")
    #expect(extract([line("교환처 : 가나다하다")]).redemptionPlace == "가나다하다")
    #expect(extract([line("교환처", y: 0.5), line("가나다해요", y: 0.55)]).redemptionPlace == "가나다해요")
  }

  @Test("앞 라벨 줄의 값이 다른 항목이면 다음 라벨 줄의 값을 쓴다")
  func usesNextLabelAfterRejectedValue() {
    let info = extract([line("교환처", y: 0.3), line("주문번호 1234", y: 0.35), line("사용처 가나다카페", y: 0.7)])
    #expect(info.redemptionPlace == "가나다카페")
  }

  @Test("안내문 라벨 줄은 교환처를 막지 않고, 값을 거른 라벨 줄은 막는다")
  func placeLabelJudgmentForModel() {
    let missingPlace = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: nil)
    let notice = [line("교환처 사정에 따라 변경될 수 있습니다")]
    let rejectedValue = [line("교환처", y: 0.5), line("주문번호 1234", y: 0.55)]

    #expect(GifticonExtractor.needsModelFill(missingPlace, textLines: notice))
    #expect(!GifticonExtractor.needsModelFill(missingPlace, textLines: rejectedValue))
    #expect(extract(rejectedValue).redemptionPlace == nil)
  }

  @Test("라벨 없는 후보가 서로 달라 비운 교환처는 모델에 묻지 않고 모델 답도 받지 않는다")
  func conflictingBrandsBlockModel() {
    let missingPlace = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: nil)
    let conflicting = [line("CU", y: 0.3), line("GS25", y: 0.4)]
    let bracketOnly = [line("[단독] 아이스 라떼 T", y: 0.3), line("가나다카페", y: 0.4)]

    #expect(extract(conflicting).redemptionPlace == nil)
    #expect(!GifticonExtractor.needsModelFill(missingPlace, textLines: conflicting))
    let filled = GifticonExtractor.filling(
      missingPlace,
      with: GifticonModelAnswer(expiryText: nil, redemptionPlace: "CU"),
      from: conflicting,
      referenceDate: Self.referenceDate,
      calendar: Self.calendar
    )
    #expect(filled.redemptionPlace == nil)
    // 괄호만 있고 확인되지 않은 이름은 후보가 아니라 모델에 묻는다.
    #expect(GifticonExtractor.needsModelFill(missingPlace, textLines: bracketOnly))
  }

  @Test(
    "안내문 라벨 줄이 있어도 라벨 낱말로 시작하는 모델 답은 교환처로 받지 않는다",
    arguments: ["교환처", "교환처 사정에", "교환처의 사정에", "유효기간", "유효기간이"]
  )
  func rejectsLabelWordModelAnswer(_ answer: String) {
    let missingPlace = GifticonInfo(expiryDate: LocalDate(year: 2026, month: 12, day: 31), redemptionPlace: nil)
    let lines = [
      line("교환처 사정에 따라 변경될 수 있습니다", y: 0.5),
      line("교환처의 사정에 따라 품절될 수 있습니다", y: 0.55),
      line("유효기간이 지난 상품은 사용할 수 없습니다", y: 0.6),
    ]

    #expect(GifticonExtractor.needsModelFill(missingPlace, textLines: lines))
    let filled = GifticonExtractor.filling(
      missingPlace,
      with: GifticonModelAnswer(expiryText: nil, redemptionPlace: answer),
      from: lines,
      referenceDate: Self.referenceDate,
      calendar: Self.calendar
    )
    #expect(filled.redemptionPlace == nil)
  }
}
