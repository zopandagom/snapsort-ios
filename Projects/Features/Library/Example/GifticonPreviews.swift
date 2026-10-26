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
  /// 여행이 없다. 보관함에 여행 줄이 없어 빈 여행 목록은 Preview "여행 - 빈 목록"에서 본다.
  case tripEmpty
  /// 장소 이름 요청이 모두 실패한다. 캐시가 없는 여행(도쿄·태평양) 상세는 1.5초 뒤 기간을 제목으로 쓴다.
  case tripGeocodingFailing
  /// 여행 목록 처음 읽기만 실패한다. 다시 시도하면 목록이 보인다.
  case tripStoreFailing
  /// 제한 접근이다. 보관함 배너와 여행 목록 안내가 보인다.
  case limited
  /// 영수증 목록 처음 읽기만 실패한다. 다시 시도하면 목록이 보인다.
  case receiptFailing
  /// 영수증이 모두 확인 중이다(데모 짝수 번은 OCR 대기, 홀수 번과 여행 영수증은 추출 대기).
  case receiptChecking
  /// 쇼핑·대화·지도 카테고리 처음 읽기만 실패한다. 다시 시도하면 격자가 보인다.
  case captureGroupFailing
  /// 검색 목록 처음 읽기만 실패한다. 검색 필드를 누르면 실패 화면이 뜨고, 다시 시도하면 결과가 보인다.
  case searchFailing
  /// 검색 목록 읽기가 1.5초 걸린다. 열자마자 입력하거나 읽는 중에 "글자 사진 추가"를 눌러 겹침을 본다.
  case searchSlow
  /// 정리 도우미: 보관함 "정리 도우미" 줄에서 만료됨·사용함 후보(추정 만료일은 기본 해제)와 캡처 인박스를 본다.
  /// 삭제하면 보관함 대역이 증분 변경을 보내 저장소 반영과 진행률이 이어진다. CU 한 장은 보관함에 없어 "건너뜀" 안내가 뜬다.
  case cleanup
  /// 정리 삭제의 첫 요청이 실패한다(알림 창, 선택 유지). 다시 누르면 성공한다.
  case cleanupDeleteFailing
  /// 정리 삭제의 첫 요청을 확인 창에서 취소한 것처럼 돌려준다(변화 없음). 다시 누르면 성공한다.
  case cleanupDeleteCancelled
  /// 정리 삭제가 2초 걸린다(확인 창이 떠 있는 동안). 그동안 다시 누르기·뒤로 갔다 오기를 본다.
  case cleanupDeleteSlow
  /// 앱 루트가 빈 영수증 목록이다. 보관함은 영수증이 없으면 줄을 숨겨 빈 목록에 갈 수 없어 루트를 바꾼다.
  case receiptEmpty

  static var current: ExampleScenario {
    UserDefaults.standard.string(forKey: "scenario").flatMap(ExampleScenario.init(rawValue:)) ?? .standard
  }
}

/// Fake 가 받은 마지막 주소·복사 값과 장소 이름 요청 수, 정리 도우미의 읽은 횟수와 삭제 요청 수를 보인다(Example 전용 디버그 줄).
/// Fake 는 관찰할 수 없어 0.5초마다 다시 읽는다.
/// 정리 화면에서 한 번 지우면 `gifticons()` 읽은 횟수가 1 늘어야 한다(변경 한 번 = 다시 읽기 한 번).
struct FakeRecordView: View {
  let map: MapClientFake
  let pasteboard: PasteboardClientFake
  var photoStore: PhotoStoreClientFake?
  var photoLibrary: PhotoLibraryClientFake?

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
      VStack(alignment: .leading, spacing: 2) {
        Text("지도로 넘긴 주소: \(self.map.openedAddresses.last ?? "없음")")
        Text("복사한 값: \(self.pasteboard.copiedTexts.last ?? "없음")")
        Text("장소 이름 요청 \(self.map.placeNameRequests.count)번")
        if let photoStore = self.photoStore, let photoLibrary = self.photoLibrary {
          let reads = "gifticons() \(photoStore.gifticonsCallCount)번 · 인박스 읽기 \(photoStore.captureInboxCallCount)번"
          Text("\(reads) · 삭제 요청 \(photoLibrary.deletionRequests.count)번")
        }
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
