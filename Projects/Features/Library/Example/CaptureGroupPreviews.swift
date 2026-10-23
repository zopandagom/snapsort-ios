import Core
import LibraryFeature
import PhotoLibraryTesting
import PhotoStoreTesting
import SwiftUI

@MainActor
private func captureGroupPreview(category: ImageCategory, photoStore: PhotoStoreClientFake) -> some View {
  NavigationStack {
    CategoryView(
      model: CategoryModel(photoLibrary: PhotoLibraryClientFake.previewAuthorized, photoStore: photoStore),
      category: category
    )
  }
}

#Preview("쇼핑 - 묶기") {
  // 툴바 묶기 메뉴에서 쇼핑몰별·브랜드별을 고른다.
  captureGroupPreview(category: .shopping, photoStore: PhotoStoreClientFake.previewClassified())
}

#Preview("대화 - 앱별") {
  captureGroupPreview(category: .chat, photoStore: PhotoStoreClientFake.previewClassified())
}

#Preview("지도 - 여러 지역") {
  // 지역별에서 한 장에 두 지역이 보이는 캡처가 서울 강남구·부산 해운대구 섹션에 모두 든다.
  captureGroupPreview(category: .map, photoStore: PhotoStoreClientFake.previewClassified())
}

#Preview("쇼핑 - 저장소 실패") {
  // 처음 읽기만 실패해, 다시 시도하면 격자가 보인다.
  captureGroupPreview(
    category: .shopping,
    photoStore: PhotoStoreClientFake.previewClassified(captureGroupItemsErrors: [0: .failed])
  )
}
