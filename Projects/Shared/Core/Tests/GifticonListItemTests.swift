import Core
import Testing

struct GifticonListItemTests {
  @Test("모델이 채운 필드만 추정이다")
  func estimatesModelFilledFields() {
    let info = GifticonInfo(
      expiryDate: gifticonDay(20_261_231),
      redemptionPlace: "스타벅스",
      modelFilledFields: [.expiryDate]
    )

    let item = GifticonListItem(asset: gifticonAsset("a"), status: .extracted(info), isUsed: false)

    #expect(item.estimatedFields == [.expiryDate])
  }

  @Test("출처를 모르는 행은 값이 있는 필드가 모두 추정이다")
  func estimatesAllValuesWhenSourcesUnknown() {
    let both = GifticonInfo(expiryDate: gifticonDay(20_261_231), redemptionPlace: "스타벅스")
    let placeOnly = GifticonInfo(expiryDate: nil, redemptionPlace: "스타벅스")
    let empty = GifticonInfo(expiryDate: nil, redemptionPlace: nil)

    func estimated(_ info: GifticonInfo) -> Set<GifticonInfo.Field> {
      GifticonListItem(asset: gifticonAsset("a"), status: .extracted(info), isUsed: false, valuesMayBeFromModel: true)
        .estimatedFields
    }

    #expect(estimated(both) == [.expiryDate, .redemptionPlace])
    #expect(estimated(placeOnly) == [.redemptionPlace])
    #expect(estimated(empty).isEmpty)
  }

  @Test("확인 중이면 추정이 없다")
  func checkingHasNoEstimates() {
    let item = GifticonListItem(asset: gifticonAsset("a"), status: .checking, isUsed: false, valuesMayBeFromModel: true)

    #expect(item.estimatedFields.isEmpty)
  }

  @Test("사용 여부만 바꾸고 나머지(추정 포함)는 그대로다")
  func changesOnlyUsage() {
    let info = GifticonInfo(expiryDate: gifticonDay(20_261_231), redemptionPlace: "스타벅스")
    let item = GifticonListItem(
      asset: gifticonAsset("a"),
      status: .extracted(info),
      isUsed: false,
      valuesMayBeFromModel: true
    )

    let used = item.with(isUsed: true)

    #expect(used.isUsed)
    #expect(used.id == item.id)
    #expect(used.status == item.status)
    #expect(used.estimatedFields == item.estimatedFields)
    #expect(used.with(isUsed: false) == item)
  }
}
