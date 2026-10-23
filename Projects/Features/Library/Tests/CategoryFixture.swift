import Core
import Foundation
import PhotoLibraryTesting
import PhotoStoreInterface
import PhotoStoreTesting
@testable import LibraryFeature

/// 화면이나 칸이 사라진 것처럼 Task 를 취소하고 끝나기를 기다린다.
@MainActor
func cancelAndWait(_ task: Task<Void, Never>) async {
  task.cancel()
  await task.value
}

extension CategoryModel {
  /// 섹션 계산을 호출 번호(0부터)마다 `gates` 에 붙잡은 뒤 기본 계산을 한다.
  static func gatedSectioning(photoStore: PhotoStoreClientFake, gates: CallGates) -> CategoryModel {
    let counter = CallCounter()
    return CategoryModel(
      photoLibrary: PhotoLibraryClientFake(),
      photoStore: photoStore,
      calendar: .seoul,
      sectioning: { items, calendar, current in
        await gates.pass(counter.next())
        return await CategorySectioning.sections(of: items, calendar: calendar, comparingTo: current)
      }
    )
  }

  /// 월 섹션은 Asia/Seoul 달력으로 나눈다.
  static func fixture(
    photoLibrary: PhotoLibraryClientFake = PhotoLibraryClientFake(),
    photoStore: PhotoStoreClientFake
  ) -> CategoryModel {
    CategoryModel(photoLibrary: photoLibrary, photoStore: photoStore, calendar: .seoul)
  }
}

extension CategoryContent {
  /// 섹션마다 식별자. 읽기 전이나 실패면 nil.
  var sectionIDs: [[ImageAsset.ID]]? {
    guard case let .loaded(sections) = self else { return nil }
    return sections.months.map { $0.assets.map(\.id) }
  }

  var sectionMonths: [ImageMonth?]? {
    guard case let .loaded(sections) = self else { return nil }
    return sections.months.map(\.month)
  }
}

extension CategorySections {
  static let empty = CategorySections(months: [], groups: [:])
}

extension IndexedImage {
  /// 생성일만 정한 분류된 이미지. 기본 카테고리는 인물이다.
  static func dated(id: String, _ creationDate: Date?, categories: Set<ImageCategory> = [.people]) -> IndexedImage {
    IndexedImage(
      asset: .stub(id: id, creationDate: creationDate),
      labels: [],
      textRecognition: .notNeeded,
      categories: categories
    )
  }
}
