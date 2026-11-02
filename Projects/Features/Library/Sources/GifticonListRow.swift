import Core
import DesignSystem
import SwiftUI

/// 기프티콘 한 줄: 썸네일·교환처·만료일·만료일 아래 D-n. 모델이 채운 값에는 "추정"을 붙인다.
/// `isStamped` 면 사용함으로 옮긴 줄이라 썸네일 색을 빼고 위에 "사용" 도장을 찍는다(장식이라 VoiceOver 는 목록 화면의 알림으로 듣는다).
struct GifticonRow: View {
  let categoryModel: CategoryModel
  let item: GifticonListItem
  let today: LocalDate
  let calendar: Calendar
  var isStamped = false

  var body: some View {
    HStack(spacing: 12) {
      CategoryThumbnailCell(model: self.categoryModel, asset: self.item.asset, category: .gifticon)
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 8))
        .photoZoomSource(self.item.asset.id, cornerRadius: 8)
        .saturation(self.isStamped ? SnapStamp.fadedSaturation : 1)
        .animation(SnapStamp.fadeAnimation, value: self.isStamped)
        .overlay {
          if self.isStamped {
            SnapStamp(text: "사용")
          }
        }
      switch self.item.status {
      case .checking:
        Text("확인 중")
          .foregroundStyle(.secondary)
        Spacer()
      case let .extracted(info):
        VStack(alignment: .leading, spacing: 4) {
          GifticonFieldText(
            info.redemptionPlace.map { Text($0) } ?? Text("교환처 모름"),
            isKnown: info.redemptionPlace != nil,
            isEstimated: self.item.estimatedFields.contains(.redemptionPlace)
          )
          .font(.body)
          GifticonFieldText(
            info.expiryDate.map { GifticonExpiryText.date($0, calendar: self.calendar) } ?? Text("만료일 모름"),
            isKnown: info.expiryDate != nil,
            isEstimated: self.item.estimatedFields.contains(.expiryDate)
          )
          .font(.subheadline)
          // 줄 오른쪽에 사용함 버튼이 있어 만료일이 잘리지 않게 D-n 배지는 만료일 아래에 둔다.
          if let expiryDate = info.expiryDate {
            GifticonDueBadge(
              due: GifticonDue(expiryDate: expiryDate, today: self.today),
              isUsed: self.item.isUsed || self.isStamped
            )
            .padding(.top, 2)
          }
        }
        Spacer(minLength: 0)
      }
    }
  }
}

/// 필드 값 한 줄. 모르는 값은 흐리게, 모델이 채운 값에는 "추정" 캡슐을 붙인다.
struct GifticonFieldText: View {
  let text: Text
  let isKnown: Bool
  let isEstimated: Bool

  init(_ text: Text, isKnown: Bool, isEstimated: Bool) {
    self.text = text
    self.isKnown = isKnown
    self.isEstimated = isEstimated
  }

  var body: some View {
    HStack(spacing: 6) {
      self.text
        .foregroundStyle(self.isKnown ? .primary : .secondary)
        .lineLimit(1)
      if self.isEstimated {
        EstimatedBadge()
      }
    }
  }
}

/// 언어 모델이 채운 값(또는 출처를 아직 모르는 옛 값) 표시.
struct EstimatedBadge: View {
  var body: some View {
    Text("추정")
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .foregroundStyle(SnapColor.lilacText)
      .background(SnapColor.lilacSoft, in: .capsule)
      .accessibilityLabel(Text("추정한 값"))
  }
}

/// D-n 배지: 오늘 만료는 "D-day", 남으면 "D-3", 지나면 "3일 지남".
/// 사용하지 않은 기프티콘이 곧 만료되면(D-day ~ D-3, `GifticonDue.isImminent`) 천천히 숨 쉬듯 커졌다 줄어든다(동작 줄이기면 멈춤).
/// 사용한 기프티콘은 "곧 만료"가 뜻이 없어 움직이지 않는다.
struct GifticonDueBadge: View {
  let due: GifticonDue
  let isUsed: Bool

  var body: some View {
    Text(self.title)
      .font(.subheadline.weight(.semibold).monospacedDigit())
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .foregroundStyle(self.style.text)
      .background(self.style.fill, in: .capsule)
      .snapPulse(self.due.isImminent && !self.isUsed)
  }

  private var title: String {
    switch self.due {
    case .remaining(days: 0): "D-day"
    case let .remaining(days): "D-\(days)"
    case let .expired(daysAgo): "\(daysAgo)일 지남"
    }
  }

  /// 7일 안이면 채운 강조색, 남으면 블러시, 지나면 중립 면. 모두 글자 대비 4.5:1 이상이다(`SnapColorTests`).
  private var style: (text: ColorToken, fill: ColorToken) {
    switch self.due {
    case let .remaining(days) where days <= 7: (SnapColor.onAccent, SnapColor.accent)
    case .remaining: (SnapColor.accent, SnapColor.blush)
    case .expired: (SnapColor.inkSecondary, SnapColor.neutral)
    }
  }
}

enum GifticonExpiryText {
  /// 만료일을 기기 달력·시간대로 쓴다. 표시 시각은 그날 정오다(자정이 없는 시간대 전환일에도 날짜가 밀리지 않고,
  /// 시간대가 바뀐 직후 한 프레임 동안 달력 사본이 옛 시간대여도 12시간 미만 차이면 같은 날짜가 보인다). 자정으로 바꾸지 않는다.
  /// 형식에도 같은 달력·시간대를 써서 Model 의 `calendar` 와 같은 날짜를 보인다.
  static func date(_ date: LocalDate, calendar: Calendar) -> Text {
    guard let noon = date.noon(in: calendar) else {
      return Text(verbatim: String(format: "%04d-%02d-%02d", date.year, date.month, date.day))
    }
    var style = Date.FormatStyle.dateTime.year().month().day()
    style.calendar = calendar
    style.timeZone = calendar.timeZone
    return Text(noon, format: style)
  }
}

extension GifticonExpirySection.Kind {
  var title: String {
    switch self {
    case .remaining: "남은 기프티콘"
    case .expired: "만료됨"
    case .unknownExpiry: "만료일 모름"
    case .checking: "확인 중"
    }
  }
}

extension GifticonListSections {
  var isEmpty: Bool {
    switch self {
    case let .byExpiry(sections): sections.isEmpty
    case let .byMonth(sections): sections.isEmpty
    }
  }
}
