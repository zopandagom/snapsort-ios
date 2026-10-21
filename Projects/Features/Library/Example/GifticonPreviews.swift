import Core
import Foundation
import ImageAnalysisTesting
import LibraryFeature
import MapTesting
import NotificationTesting
import PasteboardTesting
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
import SwiftUI

/// Example 앱 시나리오. 실행 인자 `-scenario <rawValue>` 로 고른다(예: `xcrun simctl launch <기기> <번들> -scenario gifticonEmpty`).
enum ExampleScenario: String {
  /// 기본. 모든 기프티콘 데모 상태와 주소·번호 캡처가 있다.
  case standard
  /// 기프티콘이 없다. 보관함에 기프티콘 줄이 없어 빈 목록은 Preview "기프티콘 - 빈 목록"에서 본다.
  case gifticonEmpty
  /// 기프티콘 목록 처음 읽기만 실패한다. 다시 시도하면 목록이 보인다.
  case gifticonFailing
  /// 알림을 거부했다. 보관함에 "설정에서 알림 켜기"가 보인다.
  case notificationDenied
  /// 지도 앱을 열지 못한다. 주소를 누르면 실패 안내가 뜬다.
  case mapsUnavailable

  static var current: ExampleScenario {
    UserDefaults.standard.string(forKey: "scenario").flatMap(ExampleScenario.init(rawValue:)) ?? .standard
  }
}

/// Fake 가 받은 마지막 주소·복사 값을 보인다(Example 전용 디버그 줄). Fake 는 관찰할 수 없어 0.5초마다 다시 읽는다.
struct FakeRecordView: View {
  let map: MapClientFake
  let pasteboard: PasteboardClientFake

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
      VStack(alignment: .leading, spacing: 2) {
        Text("지도로 넘긴 주소: \(self.map.openedAddresses.last ?? "없음")")
        Text("복사한 값: \(self.pasteboard.copiedTexts.last ?? "없음")")
      }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.thinMaterial, in: .rect(cornerRadius: 8))
    }
  }
}

@MainActor
func captureActionsPreviewModel(
  photoStore: PhotoStoreClientFake?,
  imageAnalysis: ImageAnalysisClientFake = .previewGifticons()
) -> CaptureActionsModel {
  CaptureActionsModel(
    photoStore: photoStore,
    imageAnalysis: imageAnalysis,
    map: MapClientFake(),
    pasteboard: PasteboardClientFake()
  )
}

extension PreviewGifticons {
  /// 기프티콘 목록에서 연 것처럼 상세에 넘길 데모 항목.
  static func item(_ index: Int) -> GifticonListItem? {
    let now = Date()
    guard let image = PreviewGifticons.images(today: LocalDate(now, calendar: .current), now: now)
      .first(where: { $0.id == PreviewPhotos.id(.gifticon, index) })
    else { return nil }
    return GifticonListItem(
      asset: image.asset,
      status: image.gifticon.map { .extracted($0) } ?? .checking,
      isUsed: self.usedIDs.contains(image.id),
      valuesMayBeFromModel: image.gifticonModelFill == .stale || image.gifticonModelFill == .sourcesUnknown
    )
  }
}

@MainActor
private func gifticonListPreview(photoStore: PhotoStoreClientFake) -> some View {
  NavigationStack {
    GifticonListView(
      model: GifticonListModel(photoStore: photoStore),
      categoryModel: CategoryModel(photoLibrary: PhotoLibraryClientFake.previewAuthorized, photoStore: photoStore)
    )
  }
}

/// 기프티콘 목록에서 연 상세(`gifticonIndex`) 또는 그 밖의 상세(nil, 문서 첫 장의 주소·번호 캡처).
@MainActor
private func detailPreview(gifticonIndex: Int?) -> some View {
  let photoStore = PhotoStoreClientFake.previewClassified()
  let item = gifticonIndex.flatMap { PreviewGifticons.item($0) }
  return NavigationStack {
    PhotoDetailView(
      model: CategoryModel(photoLibrary: PhotoLibraryClientFake.previewAuthorized, photoStore: photoStore),
      captureModel: captureActionsPreviewModel(photoStore: photoStore),
      asset: item?.asset ?? .stub(id: PreviewPhotos.id(.document, 0)),
      gifticon: item
    )
  }
}

#Preview("기프티콘 - 목록") {
  gifticonListPreview(photoStore: PhotoStoreClientFake.previewClassified())
}

#Preview("기프티콘 - 빈 목록") {
  gifticonListPreview(photoStore: PhotoStoreClientFake.previewClassified(includesGifticons: false))
}

#Preview("기프티콘 - 실패") {
  // 처음 읽기만 실패해, 다시 시도하면 목록이 보인다.
  gifticonListPreview(photoStore: PhotoStoreClientFake.previewClassified(gifticonsErrors: [0: .failed]))
}

#Preview("기프티콘 - 상세(바코드)") {
  detailPreview(gifticonIndex: 0)
}

#Preview("기프티콘 - 상세(바코드 없음)") {
  detailPreview(gifticonIndex: 3)
}

#Preview("기프티콘 - 상세(인식 실패)") {
  detailPreview(gifticonIndex: 4)
}

#Preview("상세 - 주소·번호") {
  detailPreview(gifticonIndex: nil)
}
