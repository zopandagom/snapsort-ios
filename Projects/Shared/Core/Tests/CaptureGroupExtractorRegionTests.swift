import Testing
@testable import Core

/// 테스트의 OCR 줄은 지어낸 텍스트다. 시·도 소속은 공식 자료와 대조하지 않은 값이다 (docs/ARCHITECTURE.md §4 캡처 묶음 추출).
struct CaptureGroupExtractorRegionTests {
  @Test(
    "시·도와 시·군·구가 짝이면 둘 다, 일반구는 소속 시로 올린다",
    arguments: [
      ("서울 강남구", "seoul:강남구"), ("서울특별시 중구", "seoul:중구"), ("부산 강서구", "busan:강서구"),
      ("경기도 성남시 분당구", "gyeonggi:성남시"), ("경기 분당구", "gyeonggi:성남시"), ("경기 광주시", "gyeonggi:광주시"),
      ("경기 수원시", "gyeonggi:수원시"), ("광주 서구", "gwangju:서구"), ("경남 창원시 진해구", "gyeongnam:창원시"),
      ("경북 포항시 남구", "gyeongbuk:포항시"),
    ]
  )
  func findsPair(_ text: String, _ id: String) {
    #expect(Set(CaptureGroupExtractor.regions(in: [text]).map(\.id)) == [id])
  }

  @Test(
    "시·도만 있는 줄은 줄 전체가 시·도 별칭일 때만 시·도만 지역이다",
    arguments: [
      ("제주", "jeju"),
      ("부산광역시", "busan"),
      ("광주", "gwangju"),
      ("경기도", "gyeonggi"),
      ("세종시", "sejong"),
      ("(서울)", "seoul")
    ]
  )
  func findsProvinceOnly(_ text: String, _ id: String) {
    #expect(Set(CaptureGroupExtractor.regions(in: [text]).map(\.id)) == [id])
  }

  @Test(
    "가게·글 이름 속 지명이나 단독으로 받지 않는 별칭은 시·도만으로 받지 않는다",
    arguments: ["제주 흑돼지", "부산 밀면", "대구 막창 골목", "강원도 감자탕", "서울 나들이", "경기", "세종", "세종대왕", "경기 결과"]
  )
  func doesNotFindProvinceInsideText(_ text: String) {
    #expect(CaptureGroupExtractor.regions(in: [text]).isEmpty)
  }

  @Test(
    "유일한 시·군·구 이름은 단독으로 받고, 일반구는 소속 시다",
    arguments: [
      ("해운대구", "busan:해운대구"),
      ("분당구", "gyeonggi:성남시"),
      ("(강남구)", "seoul:강남구"),
      ("해운대구 맛집", "busan:해운대구"),
      ("수원시", "gyeonggi:수원시")
    ]
  )
  func findsUniqueDistrict(_ text: String, _ id: String) {
    #expect(Set(CaptureGroupExtractor.regions(in: [text]).map(\.id)) == [id])
  }

  @Test("여러 시·도에 있는 이름과 광주시는 단독이면 빈 값이다", arguments: ["중구", "강서구", "고성군", "남구", "동구", "북구", "서구", "광주시"])
  func ambiguousDistrictAloneIsEmpty(_ text: String) {
    #expect(CaptureGroupExtractor.regions(in: [text]).isEmpty)
  }

  @Test("같은 시·도의 시·군·구 지역이 있으면 시·도만 지역은 뺀다")
  func dropsProvinceOnlyWhenDistrictExists() {
    #expect(CaptureGroupExtractor.regions(in: ["서울", "강남구"]).map(\.id) == ["seoul:강남구"])
    #expect(Set(CaptureGroupExtractor.regions(in: ["부산", "강남구"]).map(\.id)) == ["busan", "seoul:강남구"])
  }

  @Test("서로 다른 지역이 여럿이면 모두 담는다")
  func collectsEveryRegion() {
    #expect(Set(CaptureGroupExtractor.regions(in: ["강남구", "해운대구"]).map(\.id)) == ["seoul:강남구", "busan:해운대구"])
    #expect(Set(CaptureGroupExtractor.regions(in: ["서울 강남구", "서울 마포구", "제주"]).map(\.id))
      == ["seoul:강남구", "seoul:마포구", "jeju"])
  }

  @Test("짝이 맞지 않으면 각각 따로 보고, 줄을 넘어 짝짓지 않는다")
  func doesNotPairAcrossLinesOrMismatches() {
    #expect(Set(CaptureGroupExtractor.regions(in: ["부산 강남구"]).map(\.id)) == ["seoul:강남구"])
    #expect(Set(CaptureGroupExtractor.regions(in: ["서울", "중구"]).map(\.id)) == ["seoul"])
  }

  @Test("낱말이 같지 않으면 받지 않는다", arguments: ["서울역", "강남구청", "중구난방", "서울강남구", "해운대"])
  func requiresWholeWord(_ text: String) {
    #expect(CaptureGroupExtractor.regions(in: [text]).isEmpty)
  }

  @Test("지도 카테고리일 때만 지역을 담는다")
  func extractsRegionsOnlyForMap() {
    let lines = [line("서울 강남구")]

    #expect(CaptureGroupExtractor.extract(from: lines, categories: [.map]).regions.map(\.id) == ["seoul:강남구"])
    #expect(CaptureGroupExtractor.extract(from: lines, categories: [.shopping, .chat]) == .empty)
  }
}

private func line(_ text: String) -> RecognizedTextLine {
  RecognizedTextLine(text: text, confidence: 0.9, boundingBox: .init(x: 0, y: 0, width: 1, height: 0.1))
}
