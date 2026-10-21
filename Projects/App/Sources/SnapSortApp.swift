import ClassifierImpl
import Foundation
import ImageAnalysisImpl
import IndexingImpl
import LibraryFeature
import MapImpl
import NotificationImpl
import OnboardingFeature
import PasteboardImpl
import PhotoLibraryImpl
import PhotoStoreImpl
import SwiftUI
#if DEBUG
  import SampleRecorderFeature
#endif

/// 조립 지점. Client Impl 을 만들어 Feature Model 에 주입하는 곳은 여기뿐이다.
@main
struct SnapSortApp: App {
  @State private var onboardingModel: OnboardingModel
  @State private var libraryModel: LibraryModel
  @State private var categoryModel: CategoryModel
  @State private var gifticonListModel: GifticonListModel
  @State private var receiptListModel: ReceiptListModel
  @State private var captureActionsModel: CaptureActionsModel
  @State private var tripListModel: TripListModel
  @State private var tripDetailModel: TripDetailModel
  #if DEBUG
    /// Debug 빌드 전용 기록 도구 (docs/ARCHITECTURE.md §4 기록 도구).
    @State private var sampleRecorderModel: SampleRecorderModel
  #endif
  /// 분류 결과 저장 위치. 상위 폴더는 저장소 전용이며 기기 백업에서 빠진다(PhotoStoreClientImpl).
  /// 위젯 작업(W4)에서 App Group 컨테이너로 바꾼다.
  private static let photoStoreURL = URL.applicationSupportDirectory
    .appending(path: "PhotoStore", directoryHint: .isDirectory)
    .appending(path: "PhotoStore.store")

  init() {
    // 앱이 앞에 있을 때도 만료 알림이 보이게 한다. 알림이 울리기 전에 등록돼 있어야 하므로 가장 먼저 한다
    // (docs/ARCHITECTURE.md §4 만료 알림).
    NotificationClientImpl.registerForegroundPresentation()
    let photoLibrary = PhotoLibraryClientImpl()
    let imageAnalysis = ImageAnalysisClientImpl()
    self._onboardingModel = State(initialValue: OnboardingModel(photoLibrary: photoLibrary))
    // 인덱서가 쓰고 보관함 화면이 읽는 같은 저장소다.
    // 저장소를 열지 못하면(디스크 공간 부족, 손상된 저장 파일 등) 분류 없이 보관함만 보여 준다.
    let photoStore = try? PhotoStoreClientImpl(url: Self.photoStoreURL)
    let indexing = photoStore.map { photoStore in
      IndexingClientImpl(
        photoLibrary: photoLibrary,
        imageAnalysis: imageAnalysis,
        photoStore: photoStore,
        classifier: ClassifierClientImpl()
      )
    }
    self._libraryModel = State(initialValue: LibraryModel(
      photoLibrary: photoLibrary,
      indexing: indexing,
      photoStore: photoStore,
      notification: NotificationClientImpl()
    ))
    // 카테고리 화면도 같은 저장소를 읽는다. 저장소가 없으면 보관함 화면에 카테고리 줄이 없어 열리지 않는다.
    self._categoryModel = State(initialValue: CategoryModel(photoLibrary: photoLibrary, photoStore: photoStore))
    self._gifticonListModel = State(initialValue: GifticonListModel(photoStore: photoStore))
    self._receiptListModel = State(initialValue: ReceiptListModel(photoStore: photoStore))
    let map = MapClientImpl()
    // 사진 상세의 캡처 행동. 지도 앱 열기·복사는 사용자가 누를 때만 한다.
    self._captureActionsModel = State(initialValue: CaptureActionsModel(
      photoStore: photoStore,
      imageAnalysis: imageAnalysis,
      map: map,
      pasteboard: PasteboardClientImpl()
    ))
    // 여행 폴더. 목록은 지오코딩하지 않고, 상세를 열 때만 여행 중심점의 반올림 좌표로 장소 이름을 묻는다.
    self._tripListModel = State(initialValue: TripListModel(photoLibrary: photoLibrary, photoStore: photoStore))
    self._tripDetailModel = State(initialValue: TripDetailModel(photoStore: photoStore, map: map))
    #if DEBUG
      self._sampleRecorderModel = State(initialValue: SampleRecorderModel(
        photoLibrary: photoLibrary,
        imageAnalysis: imageAnalysis
      ))
    #endif
  }

  var body: some Scene {
    WindowGroup {
      // 화면 간 흐름은 App 이 정한다. 읽을 수 있는 권한이 생기면 보관함으로 넘어간다.
      if self.onboardingModel.access.canRead {
        #if DEBUG
          SampleRecorderEntry(
            libraryModel: self.libraryModel,
            categoryModel: self.categoryModel,
            gifticonListModel: self.gifticonListModel,
            receiptListModel: self.receiptListModel,
            captureActionsModel: self.captureActionsModel,
            tripListModel: self.tripListModel,
            tripDetailModel: self.tripDetailModel,
            sampleRecorderModel: self.sampleRecorderModel
          )
        #else
          LibraryView(
            model: self.libraryModel,
            categoryModel: self.categoryModel,
            gifticonListModel: self.gifticonListModel,
            receiptListModel: self.receiptListModel,
            captureActionsModel: self.captureActionsModel,
            tripListModel: self.tripListModel,
            tripDetailModel: self.tripDetailModel
          )
        #endif
      } else {
        OnboardingView(model: self.onboardingModel)
      }
    }
  }
}
