import Core
import Foundation
import Testing

struct ImageMonthSectionTests {
  @Test("같은 달끼리 묶고 최신 달부터, 달 안에서는 최신순이다")
  func groupsByMonthNewestFirst() throws {
    let calendar = try Self.calendar("UTC")
    let assets = try [
      Self.asset("sepEarly", "2026-09-01T00:00:00Z"),
      Self.asset("octLate", "2026-10-20T00:00:00Z"),
      Self.asset("sepLate", "2026-09-30T23:59:59Z"),
      Self.asset("octEarly", "2026-10-01T00:00:00Z"),
      Self.asset("lastYear", "2025-10-15T00:00:00Z"),
    ]

    let sections = ImageMonthSection.sections(of: assets, calendar: calendar)

    #expect(sections.map(\.month) == [
      ImageMonth(era: 1, year: 2026, month: 10),
      ImageMonth(era: 1, year: 2026, month: 9),
      ImageMonth(era: 1, year: 2025, month: 10),
    ])
    #expect(sections.map { $0.assets.map(\.id) } == [["octLate", "octEarly"], ["sepLate", "sepEarly"], ["lastYear"]])
  }

  @Test("같은 시각이면 식별자 순이다")
  func sameTimeOrdersByID() throws {
    let assets = try [
      Self.asset("c", "2026-10-01T00:00:00Z"),
      Self.asset("a", "2026-10-01T00:00:00Z"),
      Self.asset("b", "2026-10-01T00:00:00Z"),
    ]

    let sections = try ImageMonthSection.sections(of: assets, calendar: Self.calendar("UTC"))

    #expect(sections.map { $0.assets.map(\.id) } == [["a", "b", "c"]])
  }

  @Test("월 경계는 달력의 시간대로 정한다")
  func monthBoundaryUsesCalendarTimeZone() throws {
    let assets = try [Self.asset("a", "2026-09-30T15:30:00Z")]

    let seoul = try ImageMonthSection.sections(of: assets, calendar: Self.calendar("Asia/Seoul"))
    let utc = try ImageMonthSection.sections(of: assets, calendar: Self.calendar("UTC"))

    #expect(seoul.map(\.month) == [ImageMonth(era: 1, year: 2026, month: 10)])
    #expect(utc.map(\.month) == [ImageMonth(era: 1, year: 2026, month: 9)])
  }

  @Test("생성일 없는 이미지는 맨 뒤 하나의 섹션(month nil)에 식별자 순으로 모인다")
  func undatedImagesGoLast() throws {
    let assets = try [
      Self.asset("undatedB", nil),
      Self.asset("dated", "2026-10-01T00:00:00Z"),
      Self.asset("undatedA", nil),
    ]

    let sections = try ImageMonthSection.sections(of: assets, calendar: Self.calendar("UTC"))

    #expect(sections.map(\.month) == [ImageMonth(era: 1, year: 2026, month: 10), nil])
    #expect(sections.last?.assets.map(\.id) == ["undatedA", "undatedB"])
  }

  @Test("입력 순서와 관계없이 같은 결과다")
  func unsortedInputIsSorted() throws {
    let calendar = try Self.calendar("Asia/Seoul")
    let assets = try [
      Self.asset("a", "2026-10-20T00:00:00Z"),
      Self.asset("b", "2026-10-01T00:00:00Z"),
      Self.asset("c", "2026-08-01T00:00:00Z"),
      Self.asset("d", nil),
      Self.asset("e", "2026-08-01T00:00:00Z"),
    ]

    let expected = ImageMonthSection.sections(of: assets, calendar: calendar)

    #expect(ImageMonthSection.sections(of: assets.reversed(), calendar: calendar) == expected)
    #expect(ImageMonthSection.sections(of: [assets[3], assets[2], assets[0], assets[4], assets[1]], calendar: calendar)
      == expected)
    #expect(expected.map { $0.assets.map(\.id) } == [["a", "b"], ["c", "e"], ["d"]])
  }

  @Test("이미 정렬된 입력은 같은 시각·날짜 없음까지 그 순서 그대로 묶는다")
  func sortedInputKeepsOrder() throws {
    let assets = try [
      Self.asset("a", "2026-10-20T00:00:00Z"),
      Self.asset("b", "2026-10-20T00:00:00Z"),
      Self.asset("c", "2026-10-01T00:00:00Z"),
      Self.asset("d", "2026-08-15T00:00:00Z"),
      Self.asset("e", nil),
      Self.asset("f", nil),
    ]

    let sections = try ImageMonthSection.sections(of: assets, calendar: Self.calendar("UTC"))

    #expect(sections.map(\.month) == [
      ImageMonth(era: 1, year: 2026, month: 10),
      ImageMonth(era: 1, year: 2026, month: 8),
      nil,
    ])
    #expect(sections.flatMap(\.assets) == assets)
    #expect(sections.map { $0.assets.map(\.id) } == [["a", "b", "c"], ["d"], ["e", "f"]])
  }

  @Test("한 쌍만 어긋나도 정렬한다")
  func almostSortedInputIsSorted() throws {
    let calendar = try Self.calendar("UTC")
    let sorted = try [
      Self.asset("a", "2026-10-20T00:00:00Z"),
      Self.asset("b", "2026-10-20T00:00:00Z"),
      Self.asset("c", "2026-09-01T00:00:00Z"),
      Self.asset("d", nil),
      Self.asset("e", nil),
    ]
    let expected = ImageMonthSection.sections(of: sorted, calendar: calendar)

    for index in sorted.indices.dropLast() {
      var swapped = sorted
      swapped.swapAt(index, index + 1)
      #expect(ImageMonthSection.sections(of: swapped, calendar: calendar) == expected)
    }
  }

  @Test("이미지가 없으면 섹션이 없다")
  func emptyInputHasNoSections() throws {
    #expect(try ImageMonthSection.sections(of: [], calendar: Self.calendar("UTC")).isEmpty)
  }

  @Test("기기 달력이 일본력이면 그 달력의 연호·연·월로 묶는다")
  func japaneseCalendarUsesEra() throws {
    var japanese = Calendar(identifier: .japanese)
    japanese.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let assets = try [
      Self.asset("heisei", "2019-04-15T03:00:00Z"),
      Self.asset("reiwa", "2019-05-15T03:00:00Z"),
    ]

    let sections = ImageMonthSection.sections(of: assets, calendar: japanese)

    #expect(sections.map(\.month) == [
      ImageMonth(era: 236, year: 1, month: 5),
      ImageMonth(era: 235, year: 31, month: 4),
    ])
  }

  private static func calendar(_ timeZone: String) throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: timeZone))
    return calendar
  }

  private static func asset(_ id: String, _ date: String?) throws -> ImageAsset {
    let creationDate = try date.map { try Date($0, strategy: .iso8601) }
    return ImageAsset(
      id: id,
      creationDate: creationDate,
      coordinate: nil,
      pixelWidth: 1170,
      pixelHeight: 2532,
      isScreenshot: false
    )
  }
}
