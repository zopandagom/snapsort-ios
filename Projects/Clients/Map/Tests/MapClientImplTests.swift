import Foundation
import Testing
@testable import MapImpl

/// 주소는 지어낸 값이다 (docs/CONVENTIONS.md §3).
struct MapClientImplTests {
  @Test("지도 앱 검색 URL 은 maps scheme 에 q 하나이고, 한국어 주소를 퍼센트 인코딩한다")
  func makesMapsSearchURL() throws {
    let url = try #require(MapClientImpl.mapsURL(address: "서울특별시 중구 세종대로 110"))

    #expect(url.scheme == "maps")
    #expect(url.absoluteString
      == "maps://?q=%EC%84%9C%EC%9A%B8%ED%8A%B9%EB%B3%84%EC%8B%9C%20%EC%A4%91%EA%B5%AC%20"
      + "%EC%84%B8%EC%A2%85%EB%8C%80%EB%A1%9C%20110")
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(items == [URLQueryItem(name: "q", value: "서울특별시 중구 세종대로 110")])
  }

  @Test(
    "쿼리를 깨거나 다르게 읽힐 기호는 모두 인코딩해 디코드하면 원문이다",
    arguments: ["A+B 1-2", "a&q=b", "1#2", "로 1?2", "100%", "a/b\\c", "~._-"]
  )
  func encodesReservedCharacters(address: String) throws {
    let url = try #require(MapClientImpl.mapsURL(address: address))
    let query = try #require(url.absoluteString.split(separator: "?", maxSplits: 1).last.map(String.init))

    #expect(query.hasPrefix("q="))
    let value = String(query.dropFirst(2))
    #expect(!value.contains { "+&=#? /\\".contains($0) })
    #expect(value.removingPercentEncoding == address)
  }

  @Test("앞뒤 공백·줄바꿈을 지운다")
  func trimsWhitespace() throws {
    let url = try #require(MapClientImpl.mapsURL(address: "  세종대로 110\n"))

    #expect(url.absoluteString == "maps://?q=%EC%84%B8%EC%A2%85%EB%8C%80%EB%A1%9C%20110")
  }

  @Test("빈 주소·공백만 있는 주소는 URL 을 만들지 않는다", arguments: ["", "   ", "\n\t"])
  func rejectsBlankAddress(address: String) {
    #expect(MapClientImpl.mapsURL(address: address) == nil)
  }
}
