#if DEBUG
  import Foundation
  import Testing
  import UIKit
  import UniformTypeIdentifiers
  @testable import SampleRecorderFeature

  struct ActivityViewTests {
    @Test("공유 시트에서 메일·메시지·복사·인쇄·연락처·메모를 뺀다")
    func excludesSharingTargets() {
      let excluded = Set(ShareExclusions.activityTypes)
      let expected: [UIActivity.ActivityType] = [
        .mail, .message, .copyToPasteboard, .print, .assignToContact,
        UIActivity.ActivityType(rawValue: "com.apple.mobilenotes.SharingExtension"),
      ]

      for activityType in expected {
        #expect(excluded.contains(activityType), "\(activityType.rawValue)")
      }
    }

    @Test("제외 목록은 시스템 대상과 앱 확장 대상을 합친 것이고, AirDrop 은 남기며 겹치지 않는다")
    func exclusionListShape() {
      let activityTypes = ShareExclusions.activityTypes

      #expect(activityTypes == ShareExclusions.systemActivityTypes + ShareExclusions.appExtensionActivityTypes)
      #expect(!activityTypes.contains(.airDrop))
      #expect(Set(activityTypes).count == activityTypes.count)
    }

    @Test("파일을 쓰지 않고 파일 이름과 JSON 데이터를 그대로 넘긴다")
    @MainActor
    func itemProviderCarriesFile() async throws {
      let file = RecordedFile(fileName: "IndexingTiming-accuracy-20270115-1700.json", data: Data(#"{"a":1}"#.utf8))

      let provider = ActivityView.itemProvider(for: file)

      #expect(provider.suggestedName == file.fileName)
      #expect(provider.registeredTypeIdentifiers.contains(UTType.json.identifier))
      let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, any Error>) in
        _ = provider.loadDataRepresentation(for: .json) { data, error in
          if let data {
            continuation.resume(returning: data)
          } else {
            continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
          }
        }
      }
      #expect(data == file.data)
    }
  }
#endif
