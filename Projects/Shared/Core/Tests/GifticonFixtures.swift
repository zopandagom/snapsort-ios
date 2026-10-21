import Core
import Foundation

// 기프티콘 목록·섹션 테스트가 함께 쓰는 값. 교환처는 지어낸 텍스트다 (docs/CONVENTIONS.md §3).

/// yyyymmdd 정수로 적은 날짜. 달력에 없는 날짜면 테스트 실수라 멈춘다.
func gifticonDay(_ number: Int) -> LocalDate {
  LocalDate(year: number / 10000, month: number / 100 % 100, day: number % 100)!
}

/// 생성일을 ISO 8601 문자열로 적은 기프티콘 이미지 메타데이터.
func gifticonAsset(_ id: String, created: String? = nil) -> ImageAsset {
  ImageAsset(
    id: id,
    creationDate: created.map { ISO8601DateFormatter().date(from: $0)! },
    coordinate: nil,
    pixelWidth: 1170,
    pixelHeight: 2532,
    isScreenshot: true
  )
}

/// 추출한 기프티콘 항목. `expiry` 는 yyyymmdd 정수.
func extractedGifticon(
  _ id: String,
  expiry: Int?,
  place: String? = "스타벅스",
  created: String? = nil,
  isUsed: Bool = false
) -> GifticonListItem {
  GifticonListItem(
    asset: gifticonAsset(id, created: created),
    status: .extracted(GifticonInfo(expiryDate: expiry.map(gifticonDay), redemptionPlace: place)),
    isUsed: isUsed
  )
}

/// 추출 전 항목.
func checkingGifticon(_ id: String, created: String? = nil, isUsed: Bool = false) -> GifticonListItem {
  GifticonListItem(asset: gifticonAsset(id, created: created), status: .checking, isUsed: isUsed)
}

func gregorianCalendar(_ timeZone: String) -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: timeZone)!
  return calendar
}
