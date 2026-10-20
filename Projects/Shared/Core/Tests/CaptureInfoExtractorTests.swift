import Core
import Testing

/// 테스트의 OCR 줄은 지어낸 텍스트다(주소는 공공기관·랜드마크의 공개 주소). 실제 캡처에서 읽은 텍스트는 넣지 않는다 (docs/CONVENTIONS.md §3).
struct CaptureInfoExtractorTests {
  @Test(
    "송장 키워드 줄의 번호를 송장번호로 읽는다",
    arguments: [
      ("운송장번호 6012-3456-7890", "6012-3456-7890"),
      ("CJ대한통운 601234567890", "601234567890"),
      ("송장 번호: 1234567890", "1234567890"),
      ("우체국택배 6012345678901", "6012345678901"),
      ("운 송 장 6012-3456-7890", "6012-3456-7890"),
      ("Tracking No. 6012345678", "6012345678"),
    ]
  )
  func readsTrackingNumber(_ text: String, _ expected: String) {
    let info = CaptureInfoExtractor.extract(from: [line(text)])

    #expect(info.trackingNumbers == [CapturedText(text: expected, lineIndex: 0)])
    #expect(info.accountNumbers.isEmpty)
  }

  @Test(
    "은행·계좌 키워드 줄의 번호를 계좌번호로 읽는다",
    arguments: [
      ("국민은행 123456-01-234567", "123456-01-234567"),
      ("카카오뱅크 3333-01-1234567", "3333-01-1234567"),
      ("입금계좌: 110-123-456789", "110-123-456789"),
      ("농협 010-1234-5678-09", "010-1234-5678-09"),
      ("우체국 012345-01-234567", "012345-01-234567"),
      ("택배비 입금계좌 110-123-456789", "110-123-456789"),
      ("우체국택배 계좌 012345-01-234567", "012345-01-234567"),
      ("택배비 송금 신한은행 110-123-456789", "110-123-456789"),
    ]
  )
  func readsAccountNumber(_ text: String, _ expected: String) {
    let info = CaptureInfoExtractor.extract(from: [line(text)])

    #expect(info.accountNumbers == [CapturedText(text: expected, lineIndex: 0)])
    #expect(info.trackingNumbers.isEmpty)
  }

  @Test("키워드 줄에 번호가 없으면 번호로 시작하는 바로 다음 줄의 번호를 읽는다")
  func readsNumberOnNextLine() {
    let info = CaptureInfoExtractor.extract(from: [
      line("입금 계좌"),
      line("110-123-456789 예금주"),
      line("운송장번호"),
      line("6012-3456-7890"),
      line("GS25 반값택배"),
      line("1234567890"),
    ])

    #expect(info.accountNumbers == [CapturedText(text: "110-123-456789", lineIndex: 1)])
    #expect(info.trackingNumbers == [
      CapturedText(text: "6012-3456-7890", lineIndex: 3),
      CapturedText(text: "1234567890", lineIndex: 5),
    ])
  }

  @Test(
    "키워드 줄에 번호가 아닌 숫자가 있으면 다음 줄을 읽지 않는다",
    arguments: ["택배 기사님 010-1234-5678", "택배 도착 예정 2026-10-20", "신한은행 고객센터 1599-8000"]
  )
  func ignoresNextLineWhenKeywordLineHasOtherNumber(_ text: String) {
    let info = CaptureInfoExtractor.extract(from: [line(text), line("202610200001 주문 상품")])

    #expect(info.trackingNumbers.isEmpty)
    #expect(info.accountNumbers.isEmpty)
  }

  @Test("다음 줄이 번호로 시작하지 않으면 읽지 않는다")
  func ignoresNextLineNotStartingWithNumber() {
    let info = CaptureInfoExtractor.extract(from: [line("입금 계좌"), line("예금주 110-123-456789")])

    #expect(info.accountNumbers.isEmpty)
  }

  @Test(
    "키워드 줄이어도 송장·계좌가 아닌 번호는 읽지 않는다",
    arguments: [
      "택배 기사님 010-1234-5678",
      "택배 기사님 01012345678",
      "택배 기사 안심번호 0504-1234-5678",
      "택배 기사 안심번호 050412345678",
      "택배 기사님 +82 10-1234-5678",
      "택배 기사님 +82-10-1234-5678",
      "택배 기사님 (+82) 10-1234-5678",
      "택배 기사님 +82 (0)10-1234-5678",
      "신한은행 02-123-4567",
      "신한은행 고객센터 1599-8000",
      "택배 주문번호 A1234567890",
      "택배 도착 예정 2026-10-20",
      "은행 123456789",
      "은행 123456789012345",
    ]
  )
  func ignoresOtherNumbersOnKeywordLine(_ text: String) {
    let info = CaptureInfoExtractor.extract(from: [line(text)])

    #expect(info.trackingNumbers.isEmpty)
    #expect(info.accountNumbers.isEmpty)
  }

  @Test("키워드가 없는 줄의 긴 번호(기프티콘 번호 등)는 읽지 않는다")
  func ignoresNumbersWithoutKeyword() {
    let info = CaptureInfoExtractor.extract(from: [line("1234-5678-9012"), line("주문번호 202610200001")])

    #expect(info.trackingNumbers.isEmpty)
    #expect(info.accountNumbers.isEmpty)
  }

  @Test("같은 번호가 여러 줄에 있으면 처음 것만 둔다")
  func dropsDuplicateNumbers() {
    let info = CaptureInfoExtractor.extract(from: [
      line("운송장번호 6012-3456-7890"),
      line("CJ대한통운 601234567890"),
    ])

    #expect(info.trackingNumbers == [CapturedText(text: "6012-3456-7890", lineIndex: 0)])
  }

  @Test(
    "줄에서 도로명·지번 주소를 읽는다",
    arguments: [
      ("배송지: 서울특별시 종로구 사직로 161", "서울특별시 종로구 사직로 161"),
      ("서울 중구 세종대로 110", "서울 중구 세종대로 110"),
      ("부산광역시 해운대구 우동 1408", "부산광역시 해운대구 우동 1408"),
    ]
  )
  func readsAddress(_ text: String, _ expected: String) {
    let info = CaptureInfoExtractor.extract(from: [line("주문 정보"), line(text)])

    #expect(info.addresses == [CapturedText(text: expected, lineIndex: 1)])
  }

  @Test(
    "주소가 아닌 줄은 주소로 읽지 않는다",
    arguments: ["스타벅스 아메리카노 Tall", "유효기간 2026.12.31까지", "강남역 2번 출구", "오후 3:12", "교환처 GS25"]
  )
  func ignoresNonAddress(_ text: String) {
    #expect(CaptureInfoExtractor.extract(from: [line(text)]).addresses.isEmpty)
  }

  @Test("아무것도 없으면 빈 결과다")
  func returnsEmptyForNoLines() {
    #expect(
      CaptureInfoExtractor.extract(from: []) == CaptureInfo(addresses: [], trackingNumbers: [], accountNumbers: [])
    )
  }
}

private func line(_ text: String) -> RecognizedTextLine {
  RecognizedTextLine(text: text, confidence: 0.9, boundingBox: .zero)
}
