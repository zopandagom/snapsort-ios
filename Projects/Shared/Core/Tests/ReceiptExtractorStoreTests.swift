import Core
import Testing

/// 가게를 잘못 고르는 경로(설계 S1~S38). OCR 줄·가게 이름은 지어낸 텍스트다 (docs/CONVENTIONS.md §3).
struct ReceiptExtractorStoreTests {
  @Test(
    "섹션 머리·사본 표시 줄(가맹점 정보·판매자 정보·MERCHANT COPY)은 가게 라벨이 아니고 긴 라벨을 먼저 본다",
    arguments: [
      ReceiptPath("S1", ["[가맹점 정보]", "가맹점명 스타벅스 강남점"], storeName: "스타벅스 강남점"),
      ReceiptPath("S1 짧은 라벨만", ["[가맹점 정보]", "가맹점 예시마트"], storeName: "예시마트"),
      ReceiptPath("S2", ["판매자 정보", "판매자 예시상점"], storeName: "예시상점"),
      ReceiptPath("S3", ["MERCHANT COPY", "EXAMPLE FOODS MARKET", "TOTAL $45.20"], storeName: "EXAMPLE FOODS MARKET"),
      ReceiptPath("S5", ["가맹점번호 12345", "가맹점주소 서울시 중구", "가맹점명 예시마트"], storeName: "예시마트"),
      ReceiptPath("S6", ["상호 및 대표자", "상호 (주)예시상사 대표 홍길동"], storeName: "(주)예시상사"),
    ]
  )
  func sectionHeadersAreNotStoreLabels(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }

  @Test(
    "결제처·store·merchant 는 가게 라벨이 아니다",
    arguments: [
      ReceiptPath("S4", ["STORE #1234", "EXAMPLE JOE'S"], storeName: "EXAMPLE JOE'S"),
      ReceiptPath("S7", ["예시상점", "결제처 네이버페이", "결제금액 9,000원"], storeName: "예시상점"),
    ]
  )
  func paymentPlatformIsNotStoreLabel(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }

  @Test(
    "스크린샷 상태 막대 줄을 빼고 화면 제목·인사·버튼 줄을 건너뛴다",
    arguments: [
      ReceiptPath("S8", lines: [
        receiptLine("9:41", x: 0.05, y: 0.01, width: 0.1, height: 0.02),
        receiptLine("LTE", x: 0.75, y: 0.01, width: 0.08, height: 0.02),
        receiptLine("100%", x: 0.85, y: 0.01, width: 0.1, height: 0.02),
        receiptLine("결제 상세", y: 0.08),
        receiptLine("스타벅스 강남점", y: 0.14),
        receiptLine("결제금액 4,500원", y: 0.2),
      ], storeName: "스타벅스 강남점"),
      ReceiptPath("S14", ["안녕하세요 고객님", "결제가 완료되었습니다", "예시상점", "결제금액 9,000원"], storeName: "예시상점"),
      ReceiptPath("S15", ["닫기", "주문 상세", "예시상점"], storeName: "예시상점"),
      ReceiptPath("S16", ["*** 신용승인 ***", "예시마트"], storeName: "예시마트"),
    ]
  )
  func skipsStatusBarTitlesAndButtons(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }

  @Test("위쪽 줄 규칙: 머리글·번호·주소·날짜를 건너뛴 첫 본문 줄 위의 첫 줄이 가게다(S9)")
  func upperLineRule() {
    let info = extractReceipt([
      "영수증", "(주)예시상사", "사업자번호 000-00-00000", "서울특별시 중구 세종대로 110", "2026-10-21 12:30", "아메리카노 2 9,000",
    ])
    #expect(info.storeName == "(주)예시상사")
  }

  @Test(
    "시·도 없는 주소·미국 주소·URL·첫 본문 줄 아래 줄은 가게가 아니라 가게 모름이다",
    arguments: [
      ReceiptPath("S10", ["강남구 테헤란로 123", "아메리카노 2 9,000"]),
      ReceiptPath("S11", ["123 MAIN ST", "NEW YORK, NY 10001", "TOTAL $9.00"]),
      ReceiptPath("S12", ["www.example.com", "TEL (02) 123-4567", "합계 9,000"]),
      ReceiptPath("S13", ["2026.10.21 12:30", "아메리카노", "2 9,000"]),
    ]
  )
  func addressesAndBodyLinesAreUnknownStore(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == nil)
  }

  @Test(
    "가게 라벨 값이 비면 오른쪽 줄을 읽고, 전화·사업자 머리말부터 끊는다",
    arguments: [
      ReceiptPath("S17", lines: [
        receiptLine("가맹점명", x: 0.1, y: 0.3, width: 0.2),
        receiptLine("스타벅스 강남점", x: 0.4, y: 0.3, width: 0.4),
        receiptLine("사업자번호 000-00-00000", x: 0.1, y: 0.34, width: 0.6),
      ], storeName: "스타벅스 강남점"),
      ReceiptPath("S17 아래", ["가맹점명", "스타벅스 강남점", "사업자번호 000-00-00000"], storeName: "스타벅스 강남점"),
      ReceiptPath("S18", ["가맹점명 스타벅스 강남점 TEL 02-123-4567"], storeName: "스타벅스 강남점"),
    ]
  )
  func readsNeighborAndCutsAtHeadWords(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }

  @Test(
    "라벨 줄 아님 낱말은 첫 낱말과 같을 때만이라 용·no·tel·대표로 시작하는 가게 이름을 읽는다",
    arguments: [
      ReceiptPath("S19 용인", ["가맹점명 용인휴게소"], storeName: "용인휴게소"),
      ReceiptPath("S19 용산", ["가맹점명 용산아이파크몰점"], storeName: "용산아이파크몰점"),
      ReceiptPath("S20 NORDSTROM", ["STORE NAME: NORDSTROM RACK"], storeName: "NORDSTROM RACK"),
      ReceiptPath("S20 NOODLES", ["Merchant Name: NOODLES & CO"], storeName: "NOODLES & CO"),
      ReceiptPath("S20 Telly's", ["STORE NAME: Telly's"], storeName: "Telly's"),
      ReceiptPath("S21", ["가맹점용", "가맹점명 예시마트"], storeName: "예시마트"),
      ReceiptPath("S22", ["상호 대표떡볶이"], storeName: "대표떡볶이"),
    ]
  )
  func notStoreWordsMatchWholeWords(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }

  @Test("카드 전표 항목 줄(카드종류·유효기간·할부)은 위쪽 줄 가게가 아니다(S23)")
  func cardSlipFieldsAreNotStores() {
    let info = extractReceipt([
      "신용카드 매출전표", "카드종류 신한", "카드번호 1234-56**-****-1234", "유효기간 **/**", "할부 일시불", "거래일시 2026-10-21 12:30",
      "합계 9,000",
    ])
    #expect(info.storeName == nil)
  }

  @Test(
    "짧은 가게 라벨은 뒤 경계가 있을 때만, 긴 가게 라벨은 붙은 값도 받고, 값은 머리말 낱말과 같은 낱말에서만 끊는다",
    arguments: [
      ReceiptPath("S24", ["상호저축은행 강남지점", "결제금액 9,000원"], storeName: "상호저축은행 강남지점"),
      ReceiptPath("S25", ["가맹점명스타벅스"], storeName: "스타벅스"),
      ReceiptPath("S26", ["가맹점명 스타벅스 카드몰점 TEL 02-123-4567"], storeName: "스타벅스 카드몰점"),
    ]
  )
  func labelBoundariesAndCuts(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }

  @Test(
    "지점 이름(종로3가점·강남대로1호점)과 숫자로 시작하는 미국 가게 이름은 주소가 아니다",
    arguments: [
      ReceiptPath("S27 종로", ["스타벅스 종로3가점", "합계 9,000"], storeName: "스타벅스 종로3가점"),
      ReceiptPath("S27 명동", ["명동2가점 김밥", "합계 9,000"], storeName: "명동2가점 김밥"),
      ReceiptPath("S27 을지로", ["을지로3가역점", "합계 9,000"], storeName: "을지로3가역점"),
      ReceiptPath("S27 강남대로", ["강남대로1호점", "합계 9,000"], storeName: "강남대로1호점"),
      ReceiptPath("S27 번지", ["종로3가 123번지", "예시마트", "합계 9,000"], storeName: "예시마트"),
      ReceiptPath("S28 99", ["99 RANCH MARKET", "TOTAL $9.00"], storeName: "99 RANCH MARKET"),
      ReceiptPath("S28 365", ["365 by Example Foods", "TOTAL $9.00"], storeName: "365 by Example Foods"),
    ]
  )
  func branchNamesAreNotAddresses(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }

  @Test(
    "머리글·머리말·문장 줄은 줄 전체·첫 낱말이 같을 때만 거른다",
    arguments: [
      ReceiptPath("S29 떡", ["보기좋은떡", "합계 9,000"], storeName: "보기좋은떡"),
      ReceiptPath("S29 Copy", ["Copy Shop Plus", "TOTAL $9.00"], storeName: "Copy Shop Plus"),
      ReceiptPath("S30", ["Telly's Diner", "Table 12", "TOTAL $9.00"], storeName: "Telly's Diner"),
      ReceiptPath("S31", ["신용카드 매출전표 (고객용)", "이용해 주셔서 감사합니다", "예시마트", "합계 9,000"], storeName: "예시마트"),
    ]
  )
  func headersMatchWholeLines(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }

  @Test(
    "가게 라벨 뒤 숫자 없는 괄호 덧말을 지우고 값을 읽는다",
    arguments: [
      ReceiptPath("S32", ["가맹점명(상호) 스타벅스 강남점"], storeName: "스타벅스 강남점"),
      ReceiptPath("S33", ["상호(법인명) (주)예시상사"], storeName: "(주)예시상사"),
      ReceiptPath("S33 붙은 법인 표기", ["상호(주)예시상사"], storeName: "(주)예시상사"),
      ReceiptPath("S32 띄운 덧말", ["가맹점명 (상호) 스타벅스"], storeName: "스타벅스"),
      ReceiptPath("S6 띄운 법인 표기", ["상호 (주)예시상사"], storeName: "(주)예시상사"),
      ReceiptPath("법인 표기 (사)", ["상호 (사)예시협회"], storeName: "(사)예시협회"),
    ]
  )
  func removesLabelParentheticals(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }

  @Test(
    "조각 낱말이 든 화면 제목은 머리글이고 조각 하나뿐인 줄은 아니다",
    arguments: [
      ("CUSTOMER RECEIPT", "예시상점"), ("고객 영수증", "예시상점"), ("현금영수증(소득공제)", "예시상점"), ("이용내역 상세", "예시상점"),
      ("주문 상세 정보", "예시상점"), ("Order Details", "예시상점"), ("Transaction Summary", "예시상점"), ("상세", "상세"),
    ]
  )
  func fragmentTitles(_ title: String, _ expected: String) {
    let texts = expected == "상세" ? [title, "합계 9,000"] : [title, "예시상점", "합계 9,000"]
    #expect(extractReceipt(texts).storeName == expected)
  }

  @Test(
    "NO·TEL 로 시작하는 영문 가게 이름은 거르지 않고, 번호가 붙은 머리말 줄은 계속 거른다",
    arguments: [
      ReceiptPath("S36 위쪽", ["NO BRAND BURGER", "TOTAL $9.00"], storeName: "NO BRAND BURGER"),
      ReceiptPath("S36 라벨", ["Merchant Name: NO BRAND BURGER"], storeName: "NO BRAND BURGER"),
      ReceiptPath("S37 위쪽", ["TEL AVIV GRILL", "TEL (02) 123-4567", "TOTAL $9.00"], storeName: "TEL AVIV GRILL"),
      ReceiptPath("S37 라벨", ["STORE NAME: TEL AVIV GRILL"], storeName: "TEL AVIV GRILL"),
      ReceiptPath("S38 위쪽", ["No. 0012", "Table 12", "SERVER: KIM", "예시식당", "합계 9,000"], storeName: "예시식당"),
      ReceiptPath("S38 라벨", ["가맹점 NO 12345", "가맹점명 예시마트"], storeName: "예시마트"),
      ReceiptPath("S38 번호 값", ["예시마트", "가맹점 NO 12345", "합계 9,000"], storeName: "예시마트"),
      ReceiptPath("S38 전화 값", ["가맹점 TEL 02-123-4567", "예시마트", "합계 9,000"], storeName: "예시마트"),
    ]
  )
  func englishHeadWords(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }

  @Test("취소 전표 이름·상태 문구 줄은 위쪽 줄 가게가 아니다")
  func cancelTitlesAreNotStores() {
    #expect(extractReceipt(["*** 취소 매출전표 ***", "예시마트", "합계 9,000"]).storeName == "예시마트")
    #expect(extractReceipt(["VOID", "EXAMPLE FOODS", "TOTAL $3.49"]).storeName == "EXAMPLE FOODS")
  }

  @Test(
    "일본어·중국어 인사·머리글·문장·주소·품목 머리 줄은 가게가 아니고 가게 라벨은 붙은 값도 받는다",
    arguments: [
      ReceiptPath("S39", ["いらっしゃいませ", "ローソン 渋谷店", "合計 ¥1,100"], storeName: "ローソン 渋谷店"),
      ReceiptPath("S40", ["東京都渋谷区道玄坂1-2-3", "TEL 03-1234-5678", "合計 ¥1,100"]),
      ReceiptPath("S41", ["北京市朝阳区建国路88号", "欢迎光临", "合计 ¥88.00", "元"]),
      ReceiptPath("S42 붙음", ["品名数量金額", "合計 ¥1,100"]),
      ReceiptPath("S42 띄움", ["品名 数量 金額", "合計 ¥1,100"]),
      ReceiptPath("S44 띄움", ["店舗名 ローソン渋谷店"], storeName: "ローソン渋谷店"),
      ReceiptPath("S44 붙음", ["店名ローソン"], storeName: "ローソン"),
      ReceiptPath("S45", ["ありがとうございました", "合計 ¥1,100"]),
      ReceiptPath("S49", ["渋谷区道玄坂1-2-3", "合計 ¥1,100"]),
    ]
  )
  func japaneseAndChineseLines(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }

  @Test(
    "3자 이상 머리말은 시작만으로, 2자 머리말은 같거나 바로 뒤가 숫자일 때만 거르고, 주소 규칙은 지점 이름을 거르지 않는다",
    arguments: [
      ReceiptPath("S43", ["대표자홍길동", "합계 9,000"]),
      ReceiptPath("S46 役所", ["渋谷区役所前店", "合計 ¥1,100"], storeName: "渋谷区役所前店"),
      ReceiptPath("S46 市", ["札幌市中央区店", "合計 ¥1,100"], storeName: "札幌市中央区店"),
      ReceiptPath("S48 레저", ["レジャーランド", "合計 ¥1,100"], storeName: "レジャーランド"),
      ReceiptPath("S48 레지", ["レジ0001", "ローソン", "合計 ¥1,100"], storeName: "ローソン"),
      ReceiptPath("S51", ["거래구분신용취소", "예시마트", "합계 9,000"], storeName: "예시마트"),
      ReceiptPath("S52", ["取消", "ローソン", "合計 ¥1,100"], storeName: "ローソン"),
    ]
  )
  func headWordLengthsAndAddresses(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }

  @Test(
    "끊는 말의 부분 문자열 대조는 값 범위에서만이라 할인·포인트로 시작하는 가게 이름은 그대로다(S50)과 r3.1 회귀(S47)",
    arguments: [
      ReceiptPath("S50 할인", ["할인마트", "합계 9,000"], storeName: "할인마트"),
      ReceiptPath("S50 포인트", ["포인트카페", "합계 9,000"], storeName: "포인트카페"),
      ReceiptPath("S47 S19", ["가맹점명 용인휴게소"], storeName: "용인휴게소"),
      ReceiptPath("S47 S20", ["STORE NAME: NORDSTROM RACK"], storeName: "NORDSTROM RACK"),
      ReceiptPath("S47 S22", ["상호 대표떡볶이"], storeName: "대표떡볶이"),
      ReceiptPath("S47 S24", ["상호저축은행 강남지점", "결제금액 9,000원"], storeName: "상호저축은행 강남지점"),
      ReceiptPath("S47 S26", ["가맹점명 스타벅스 카드몰점 TEL 02-123-4567"], storeName: "스타벅스 카드몰점"),
      ReceiptPath("S47 S37", ["STORE NAME: TEL AVIV GRILL"], storeName: "TEL AVIV GRILL"),
    ]
  )
  func substringCutsOnlyInValueRange(_ path: ReceiptPath) {
    #expect(path.extracted.storeName == path.storeName)
  }
}
