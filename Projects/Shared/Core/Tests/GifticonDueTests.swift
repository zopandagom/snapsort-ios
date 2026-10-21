import Core
import Testing

struct GifticonDueTests {
  @Test(
    "만료일 당일은 D-day, 앞은 D-n, 지나면 지난 일수다(연말·윤년 경계)",
    arguments: [
      (20_261_019, 20_261_019, GifticonDue.remaining(days: 0)),
      (20_261_019, 20_261_020, .remaining(days: 1)),
      (20_261_019, 20_261_018, .expired(daysAgo: 1)),
      (20_261_231, 20_270_101, .remaining(days: 1)),
      (20_270_101, 20_261_231, .expired(daysAgo: 1)),
      (20_280_228, 20_280_301, .remaining(days: 2)),
      (20_270_228, 20_270_301, .remaining(days: 1)),
      (20_280_229, 20_280_229, .remaining(days: 0)),
      (21_000_228, 21_000_301, .remaining(days: 1)),
      (20_280_301, 20_280_228, .expired(daysAgo: 2)),
    ]
  )
  func countsDays(today: Int, expiry: Int, expected: GifticonDue) {
    #expect(GifticonDue(expiryDate: gifticonDay(expiry), today: gifticonDay(today)) == expected)
  }
}
