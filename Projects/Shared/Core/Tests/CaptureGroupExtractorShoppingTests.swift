import Testing
@testable import Core

/// 테스트의 OCR 줄은 지어낸 텍스트다. 실제 캡처에서 읽은 텍스트는 넣지 않는다 (docs/CONVENTIONS.md §3).
struct CaptureGroupExtractorShoppingTests {
  @Test(
    "몰 이름·서비스 이름·도메인·이어 붙인 낱말로 쇼핑몰을 찾는다",
    arguments: [
      ("쿠팡", "coupang"), ("로켓배송 도착", "coupang"), ("https://m.coupang.com/vp/products/1", "coupang"),
      ("m.coupang.com/vp/1", "coupang"), ("LOTTE ON 특가", "lotteOn"), ("Smart Store", "naverShopping"),
      ("smartstore.naver.com/example", "naverShopping"), ("무신사 스토어", "musinsa"), ("11번가 슈팅배송", "elevenStreet"),
      ("SSG.COM", "ssg"), ("ssg", "ssg"), ("당근", "daangn"), ("(오늘의집)", "ohouse"),
    ]
  )
  func findsMall(_ text: String, _ id: String) {
    #expect(CaptureGroupExtractor.mall(in: [text])?.id == id)
  }

  @Test("서로 다른 몰이 둘 이상 보이면 몰을 정하지 않고, 같은 몰이 여러 번 보이면 그 몰이다")
  func twoMallsAreEmpty() {
    #expect(CaptureGroupExtractor.mall(in: ["쿠팡 12,000원", "11번가 12,500원"]) == nil)
    #expect(CaptureGroupExtractor.mall(in: ["쿠팡 12,000원", "로켓배송", "coupang.com"])?.id == "coupang")
  }

  @Test(
    "일반 낱말이기도 한 이름은 줄 전체일 때만 받고, 같음 대조라 조사나 다른 서비스는 받지 않는다",
    arguments: ["당근 2kg", "지그재그 패턴 니트", "쿠팡이츠", "쿠팡에서 샀어요", "naver.com", "네이버페이", "스마일배송"]
  )
  func doesNotFindMall(_ text: String) {
    #expect(CaptureGroupExtractor.mall(in: [text]) == nil)
  }

  @Test("줄 별칭은 줄 전체가 그 이름일 때 받는다")
  func lineAliasNeedsWholeLine() {
    #expect(CaptureGroupExtractor.mall(in: ["지그재그"])?.id == "zigzag")
    #expect(CaptureGroupExtractor.mall(in: ["옥션"])?.id == "auction")
    #expect(CaptureGroupExtractor.mall(in: ["Auction"])?.id == "auction")
  }

  @Test(
    "브랜드 이름·이어 붙인 낱말·아포스트로피·정규 동등으로 브랜드를 찾는다",
    arguments: [
      ("나이키 에어맥스 90", "nike"), ("The North Face", "theNorthFace"), ("NEW BALANCE 530", "newBalance"), ("H&M", "hm"),
      ("Arc'teryx", "arcteryx"), ("Hermès", "hermes"), ("Hermes", "hermes"), ("무인양품", "muji"), ("다이슨 청소기", "dyson"),
    ]
  )
  func findsBrand(_ text: String, _ id: String) {
    #expect(CaptureGroupExtractor.brand(in: [text])?.id == id)
  }

  @Test("이름이 일반 낱말이기도 한 브랜드는 줄 전체일 때만 받는다")
  func wordLikeBrandsNeedWholeLine() {
    #expect(CaptureGroupExtractor.brand(in: ["Apple"])?.id == "apple")
    #expect(CaptureGroupExtractor.brand(in: ["애플"])?.id == "apple")
    #expect(CaptureGroupExtractor.brand(in: ["삼성"])?.id == "samsung")
    #expect(CaptureGroupExtractor.brand(in: ["필립스"])?.id == "philips")
    #expect(CaptureGroupExtractor.brand(in: ["레고"])?.id == "lego")
    for text in ["apple 주스", "애플 망고", "삼성 카드", "필립스 드라이버 세트", "자라 거북이", "코치 선생님", "gap 년"] {
      #expect(CaptureGroupExtractor.brand(in: [text]) == nil)
    }
  }

  @Test(
    "제품 이름은 브랜드 별칭이 아니고, 액세서리·호환 줄은 브랜드를 찾지 않는다",
    arguments: [
      "아이폰 17 케이스", "닌텐도 스위치 호환 케이스", "다이슨 거치대", "Apple Watch 밴드", "Case for iPhone", "iPhone 17 Pro",
      "레고 호환 블록", "삼성전자 충전기", "폰 스킨 나이키", "나이키 아이폰케이스",
    ]
  )
  func skipsAccessoryLines(_ text: String) {
    #expect(CaptureGroupExtractor.brand(in: [text]) == nil)
  }

  @Test("스킨케어·커버력처럼 낱말이 다르면 액세서리 줄이 아니다")
  func accessoryWordsMatchWholeWords() {
    #expect(CaptureGroupExtractor.brand(in: ["설화수 자음수 스킨"]) == nil)
    #expect(CaptureGroupExtractor.brand(in: ["라네즈 네오쿠션 커버력"])?.id == "laneige")
    #expect(CaptureGroupExtractor.brand(in: ["이니스프리 스킨케어"])?.id == "innisfree")
  }

  @Test("브랜드가 둘 이상 보이면 정하지 않고, 같은 브랜드 여러 번은 그 브랜드다")
  func twoBrandsAreEmpty() {
    #expect(CaptureGroupExtractor.brand(in: ["나이키 에어맥스", "아디다스 슈퍼스타"]) == nil)
    #expect(CaptureGroupExtractor.brand(in: ["나이키 에어맥스", "NIKE 신상"])?.id == "nike")
    // 액세서리 줄은 건너뛰므로 남은 브랜드가 하나면 그 브랜드다.
    #expect(CaptureGroupExtractor.brand(in: ["나이키 에어맥스", "다이슨 거치대"])?.id == "nike")
  }

  @Test("쇼핑 카테고리일 때만 몰·브랜드를 담는다")
  func extractsShoppingOnlyForShopping() {
    let lines = ["쿠팡", "나이키 에어맥스"].map(line)

    let shopping = CaptureGroupExtractor.extract(from: lines, categories: [.shopping])
    #expect(shopping.mall?.id == "coupang")
    #expect(shopping.brand?.id == "nike")
    #expect(CaptureGroupExtractor.extract(from: lines, categories: [.chat]) == .empty)
    #expect(CaptureGroupExtractor.extract(from: lines, categories: [.document, .receipt]) == .empty)
  }
}

private func line(_ text: String) -> RecognizedTextLine {
  RecognizedTextLine(text: text, confidence: 0.9, boundingBox: .init(x: 0, y: 0, width: 1, height: 0.1))
}
