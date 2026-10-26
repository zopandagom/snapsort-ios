#if DEBUG
  import LibraryFeature
  import SampleRecorderFeature
  import SwiftUI

  /// Debug 빌드에서 보관함 화면 위에 기록 도구(SampleRecorderFeature) 진입 버튼을 얹는다 (docs/ARCHITECTURE.md §4 기록 도구).
  /// 기록 화면은 루트를 바꿔 보여 준다. 보관함 화면이 사라지며 그 `.task` 가 취소되어 인덱서가 멈추므로 측정과 겹치지 않는다.
  struct SampleRecorderEntry: View {
    let libraryModel: LibraryModel
    let categoryModel: CategoryModel
    let gifticonListModel: GifticonListModel
    let receiptListModel: ReceiptListModel
    let captureActionsModel: CaptureActionsModel
    let tripListModel: TripListModel
    let tripDetailModel: TripDetailModel
    let searchModel: SearchModel
    let cleanupModel: CleanupModel
    let captureInboxModel: CaptureInboxModel
    let sampleRecorderModel: SampleRecorderModel

    /// 화면 전환만 정하는 일시 상태.
    @State private var isShowingRecorder = false

    var body: some View {
      if self.isShowingRecorder {
        SampleRecorderView(model: self.sampleRecorderModel) {
          self.isShowingRecorder = false
        }
      } else {
        LibraryView(
          model: self.libraryModel,
          categoryModel: self.categoryModel,
          gifticonListModel: self.gifticonListModel,
          receiptListModel: self.receiptListModel,
          captureActionsModel: self.captureActionsModel,
          tripListModel: self.tripListModel,
          tripDetailModel: self.tripDetailModel,
          searchModel: self.searchModel,
          cleanupModel: self.cleanupModel,
          captureInboxModel: self.captureInboxModel
        )
        // 오른쪽 가운데에 얹는다. 아래쪽은 iOS 26 검색 필드, 위쪽은 화면마다 툴바 버튼이 차지한다.
        .overlay(alignment: .trailing) {
          Button("기록") {
            self.isShowingRecorder = true
          }
          .buttonStyle(.bordered)
          .font(.caption)
          .padding(.trailing, 4)
        }
      }
    }
  }
#endif
