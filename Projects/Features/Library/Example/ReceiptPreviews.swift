import LibraryFeature
import PhotoLibraryTesting
import PhotoStoreTesting
import SwiftUI

@MainActor
private func receiptListPreview(photoStore: PhotoStoreClientFake) -> some View {
  NavigationStack {
    ReceiptListView(
      model: ReceiptListModel(photoStore: photoStore),
      categoryModel: CategoryModel(photoLibrary: PhotoLibraryClientFake.previewAuthorized, photoStore: photoStore)
    )
  }
}

#Preview("영수증 - 목록") {
  receiptListPreview(photoStore: PhotoStoreClientFake.previewClassified())
}

#Preview("영수증 - 빈 목록") {
  // 보관함은 영수증이 없으면 영수증 카드를 숨기므로 여기서 본다(앱은 `-scenario receiptEmpty`).
  receiptListPreview(photoStore: PhotoStoreClientFake())
}

#Preview("영수증 - 저장소 실패") {
  // 처음 읽기만 실패해, 다시 시도하면 목록이 보인다.
  receiptListPreview(photoStore: PhotoStoreClientFake.previewClassified(receiptsErrors: [0: .failed]))
}

#Preview("영수증 - 확인 중") {
  receiptListPreview(photoStore: PhotoStoreClientFake.previewClassified(allReceiptsChecking: true))
}
