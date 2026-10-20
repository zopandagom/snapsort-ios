import Core
import Testing

/// 테스트의 OCR 줄은 지어낸 텍스트다(주소는 공공기관·랜드마크의 공개 주소이거나 지어낸 주소). 실제 캡처에서 읽은 텍스트는 넣지 않는다 (docs/CONVENTIONS.md §3).
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
      ("신한은행 010-1234-5678", "010-1234-5678"),
      ("기업은행 01012345678", "01012345678"),
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

  @Test("라벨 아래 줄의 휴대폰 번호 계좌는 라벨이나 그 줄에 은행 이름이 있을 때만 읽는다")
  func readsMobileAccountOnNextLineOnlyWithBankName() {
    let withBankBelow = CaptureInfoExtractor.extract(from: [line("입금 계좌"), line("010-1234-5678 신한은행")])
    let withBankLabel = CaptureInfoExtractor.extract(from: [line("신한은행"), line("010-1234-5678")])
    let withoutBank = CaptureInfoExtractor.extract(from: [line("입금 계좌"), line("010-1234-5678 로 연락 주세요")])

    #expect(withBankBelow.accountNumbers == [CapturedText(text: "010-1234-5678", lineIndex: 1)])
    #expect(withBankLabel.accountNumbers == [CapturedText(text: "010-1234-5678", lineIndex: 1)])
    #expect(withoutBank.accountNumbers.isEmpty)
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
      "입금 후 010-1234-5678 로 문자 주세요",
      "계좌 문의 01012345678",
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
      ("서울 마포구 연남동 223-14", "서울 마포구 연남동 223-14"),
      ("경기도 성남시 분당구 판교역로 166번길 10", "경기도 성남시 분당구 판교역로 166번길 10"),
      ("서울 강남구 역삼로12길 34", "서울 강남구 역삼로12길 34"),
      ("경기도 양평군 양평읍 양근리 123", "경기도 양평군 양평읍 양근리 123"),
      ("세종특별자치시 한누리대로 2130", "세종특별자치시 한누리대로 2130"),
      ("서울특별시 종로구 종로1가 1", "서울특별시 종로구 종로1가 1"),
      ("제주특별자치도 제주시 첨단로 242 (영평동)", "제주특별자치도 제주시 첨단로 242"),
      ("주소 서울 강남구 테헤란로 123 4층", "서울 강남구 테헤란로 123"),
      ("부산광역시 해운대구 우동 1408번지", "부산광역시 해운대구 우동 1408"),
      ("세종 조치원읍 군청로 93", "세종 조치원읍 군청로 93"),
      ("세종특별자치시 한솔동 123", "세종특별자치시 한솔동 123"),
      ("세종특별자치시 갈매로 388", "세종특별자치시 갈매로 388"),
      ("세종시 가름로 143", "세종시 가름로 143"),
      ("서울특별시 중구 세종대로 110(태평로1가)", "서울특별시 중구 세종대로 110"),
      ("부산광역시 해운대구 우동 1408번지, 2층", "부산광역시 해운대구 우동 1408"),
      ("경기도 용인시 처인구 포곡읍 에버랜드로 199", "경기도 용인시 처인구 포곡읍 에버랜드로 199"),
      ("경상남도 창원시 마산합포구 구산면 구서리 123", "경상남도 창원시 마산합포구 구산면 구서리 123"),
      ("충청북도 청주시 상당구 낭성면 관정리 45", "충청북도 청주시 상당구 낭성면 관정리 45"),
      ("주소:서울 마포구 연남동 223-14,", "서울 마포구 연남동 223-14"),
      ("강원특별자치도 고성군 토성면 봉포리 산 12", "강원특별자치도 고성군 토성면 봉포리 산 12"),
    ]
  )
  func readsAddress(_ text: String, _ expected: String) {
    let info = CaptureInfoExtractor.extract(from: [line("주문 정보"), line(text)])

    #expect(info.addresses == [CapturedText(text: expected, lineIndex: 1)])
  }

  @Test(
    "주소가 아닌 줄은 주소로 읽지 않는다",
    arguments: [
      "스타벅스 아메리카노 Tall",
      "유효기간 2026.12.31까지",
      "강남역 2번 출구",
      "오후 3:12",
      "교환처 GS25",
      "서울 3호선 2번 출구",
      "부산 여행 2박 3일",
      "대구 수성구 맛집 1위",
      "남서울 중구 세종대로 110",
      "강남구 역삼동",
      "서울 날씨가 30도",
      "부산 방향으로 2km",
      "서울 기준으로 3시간",
      "서울 전세가 5억",
      "서울 출근길 30분",
      "서울 강남구 도보로 5분",
      "서울 중구 날씨가 30도",
      "경기 끝나면 우리 2-1 승",
      "경기 다시 서로 1:1",
      "부산 가면 거리 1 위",
      "대구 가면 따로 1 번 출구",
      "서울 다시 이동 3 회",
      "세종 가면 바로 3",
      "세종 이후로 3",
      "세종 아무리 3",
      "세종 운동 3",
      "서울 강남구 가면 테헤란로 3",
      "세종 종로1가 3",
      "서울 축구 우리 2-1",
      "서울 가면 바로 010-1234-5678",
      "서울 강남구 서초동 2.5",
      "서울 강남구 역삼동 010-1234-5678",
    ]
  )
  func ignoresNonAddress(_ text: String) {
    #expect(CaptureInfoExtractor.extract(from: [line(text)]).addresses.isEmpty)
  }

  @Test("한 줄에 주소가 둘이면 둘 다 읽는다")
  func readsTwoAddressesOnOneLine() {
    let info = CaptureInfoExtractor.extract(from: [line("서울 중구 세종대로 110 → 부산광역시 해운대구 우동 1408")])

    #expect(info.addresses == [
      CapturedText(text: "서울 중구 세종대로 110", lineIndex: 0),
      CapturedText(text: "부산광역시 해운대구 우동 1408", lineIndex: 0),
    ])
  }

  @Test("같은 주소가 여러 줄에 있으면 처음 것만 둔다")
  func dropsDuplicateAddresses() {
    let info = CaptureInfoExtractor.extract(from: [
      line("배송지 서울 중구 세종대로 110"),
      line("서울 중구 세종대로 110"),
    ])

    #expect(info.addresses == [CapturedText(text: "서울 중구 세종대로 110", lineIndex: 0)])
  }

  @Test("한글 라벨 뒤의 영문 주소는 기기의 주소 감지로 읽는다")
  func readsNonKoreanAddressAfterKoreanLabel() {
    let info = CaptureInfoExtractor.extract(from: [line("주소: 1 Infinite Loop, Cupertino, CA 95014")])

    #expect(info.addresses == [CapturedText(text: "1 Infinite Loop, Cupertino, CA 95014", lineIndex: 0)])
  }

  @Test("한글이 없는 줄은 기기의 주소 감지로 읽는다")
  func readsNonKoreanAddressWithDetector() {
    let info = CaptureInfoExtractor.extract(from: [line("1 Infinite Loop, Cupertino, CA 95014")])

    #expect(info.addresses == [CapturedText(text: "1 Infinite Loop, Cupertino, CA 95014", lineIndex: 0)])
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
