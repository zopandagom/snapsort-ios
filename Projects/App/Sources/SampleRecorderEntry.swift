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
    let captureActionsModel: CaptureActionsModel
    let tripListModel: TripListModel
    let tripDetailModel: TripDetailModel
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
          captureActionsModel: self.captureActionsModel,
          tripListModel: self.tripListModel,
          tripDetailModel: self.tripDetailModel
        )
        .overlay(alignment: .bottomLeading) {
          Button("기록") {
            self.isShowingRecorder = true
          }
          .buttonStyle(.bordered)
          .font(.caption)
          .padding()
        }
      }
    }
  }
#endif
