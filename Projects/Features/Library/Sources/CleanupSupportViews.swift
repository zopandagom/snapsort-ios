import Core
import DesignSystem
import SwiftUI

/// 정리 화면과 캡처 인박스가 함께 쓰는 조각 (docs/ARCHITECTURE.md §4 정리 도우미).

/// 제한 접근 안내. 화면 위에 덧대지 않고 목록 첫 섹션으로 둔다.
struct CleanupLimitedSection: View {
  let selectMore: () -> Void

  var body: some View {
    Section {
      HStack {
        Label("선택한 사진 안에서만 정리합니다", systemImage: "photo.badge.checkmark")
          .font(.subheadline)
        Spacer()
        Button("사진 더 선택", action: self.selectMore)
          .buttonStyle(.snapSecondary)
          .font(.subheadline)
      }
    }
  }
}

/// 삭제 결과 안내. 지운 수가 0 이면 건너뜀만 알린다.
struct CleanupNoticeSection: View {
  let notice: CleanupNotice
  let dismiss: () -> Void

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        if self.notice.deletedCount > 0 {
          Text("\(self.notice.deletedCount)장을 지웠습니다. '최근 삭제된 항목'에 30일 동안 남고, 비우면 저장 공간이 확보됩니다.")
        }
        if self.notice.skippedCount > 0 {
          Text("\(self.notice.skippedCount)장은 이미 보관함에 없어 건너뛰었습니다.")
        }
        Button("닫기", action: self.dismiss)
          .buttonStyle(.borderless)
      }
      .font(.subheadline)
    }
  }
}

/// 목록 끝의 작은 안내 한 줄.
struct CleanupFootnote: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(self.text)
      .font(.footnote)
      .foregroundStyle(.secondary)
      .listRowBackground(Color.clear)
  }
}

enum CleanupText {
  /// 확보 용량 추정치 문구. 파일 크기를 읽지 않고 셈한 값이다. 0 도 "Zero KB" 같은 말 대신 숫자로 보인다.
  static func bytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: bytes)
  }

  /// 비슷한 사진의 촬영 시각(초까지). 기기 달력(`CleanupModel.calendar`)의 달력 체계·시간대로 쓴다. 로캘은 화면 환경 로캘이다.
  static func photoTimeStyle(calendar: Calendar) -> Date.FormatStyle {
    var style = Date.FormatStyle.dateTime.year().month().day().hour().minute().second()
    style.calendar = calendar
    style.timeZone = calendar.timeZone
    return style
  }

  static let sizeEstimateNote = "확보 용량은 사진 크기로 셈한 추정치입니다. iCloud 사진 최적화를 쓰면 실제로 확보되는 공간이 다를 수 있습니다."
}

extension CleanupSection.Kind {
  var title: String {
    switch self {
    case .expiredGifticons: "만료된 기프티콘"
    case .usedGifticons: "사용한 기프티콘"
    case .similarPhotos: "비슷한 사진"
    }
  }
}

extension View {
  /// 지우지 못했거나 보관하지 못했을 때 알림 창을 띄운다. 확인을 누르면 `dismiss` 를 부른다.
  func cleanupAlert(_ alert: CleanupAlert?, dismiss: @escaping () -> Void) -> some View {
    self.alert(
      "정리 도우미",
      isPresented: Binding(get: { alert != nil }, set: {
        if !$0 {
          dismiss()
        }
      })
    ) {
      Button("확인") {}
    } message: {
      Text(alert?.message ?? "")
    }
  }
}

extension CleanupAlert {
  var message: String {
    switch self {
    case .deleteNotAuthorized: "사진을 지울 권한이 없습니다. 설정에서 사진 접근을 확인해 주세요."
    case .deleteFailed: "사진을 지우지 못했습니다. 다시 시도해 주세요."
    case .keepFailed: "보관하지 못했습니다. 다시 시도해 주세요."
    }
  }
}
