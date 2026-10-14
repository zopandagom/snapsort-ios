// Debug 전용: SampleRecorderModel.swift 머리 주석 참고
#if DEBUG
  import CoreTransferable
  import SwiftUI
  import UIKit
  import UniformTypeIdentifiers

  /// 시스템 공유 시트. 결과 파일에 OCR 텍스트가 있으므로 공개 상수가 있는 시스템 대상과 Apple 앱 공유 확장(메모 등. 비공개 식별자라 빠지지 않을 수 있다)을
  /// 뺀다(`ShareExclusions`).
  /// 그 밖의 대상과 '파일에 저장'의 iCloud Drive 위치는 코드로 막을 수 없어 화면 안내로 둔다 (docs/CONVENTIONS.md §4).
  struct ActivityView: UIViewControllerRepresentable {
    let file: RecordedFile
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
      let controller = UIActivityViewController(
        activityItemsConfiguration: UIActivityItemsConfiguration(itemProviders: [Self.itemProvider(for: self.file)])
      )
      controller.excludedActivityTypes = ShareExclusions.activityTypes
      let onComplete = self.onComplete
      controller.completionWithItemsHandler = { _, _, _, _ in onComplete() }
      return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    /// 파일을 쓰지 않고 Data 로 넘긴다. `RecordedFile` 의 Transferable 표현(json, 제안 파일 이름)을 그대로 쓴다.
    static func itemProvider(for file: RecordedFile) -> NSItemProvider {
      let provider = NSItemProvider()
      provider.register(file)
      provider.suggestedName = file.fileName
      return provider
    }
  }

  enum ShareExclusions {
    /// 공개 상수가 있는 시스템 대상.
    static var systemActivityTypes: [UIActivity.ActivityType] {
      [
        .mail, .message, .copyToPasteboard, .print, .assignToContact, .addToReadingList, .openInIBooks, .markupAsPDF,
        .saveToCameraRoll, .postToFacebook, .postToTwitter, .postToWeibo, .postToTencentWeibo, .postToFlickr,
        .postToVimeo, .sharePlay, .collaborationInviteWithLink, .collaborationCopyLink,
      ]
    }

    /// 공개 상수가 없는 Apple 앱 공유 확장. 메모처럼 iCloud 로 동기화되는 앱이라 뺀다.
    /// 비공개 식별자라 iOS 가 바꿀 수 있다. 실기기에서 확인하지 않은 후보값이다(PR 본문의 실기기 확인 항목). 시트에 남으면 실제 값으로 고친다.
    static var appExtensionActivityTypes: [UIActivity.ActivityType] {
      [
        UIActivity.ActivityType(rawValue: "com.apple.mobilenotes.SharingExtension"), // 메모
        UIActivity.ActivityType(rawValue: "com.apple.reminders.sharingextension"), // 미리 알림
        UIActivity.ActivityType(rawValue: "com.apple.freeform.sharingextension"), // Freeform
      ]
    }

    static var activityTypes: [UIActivity.ActivityType] {
      self.systemActivityTypes + self.appExtensionActivityTypes
    }
  }
#endif
