import Core
import Foundation
import PhotoStoreInterface
import SwiftData

// 특징 벡터 저장·소급과 비슷한 사진 묶기 입력 (docs/ARCHITECTURE.md §4 저장소·정리 도우미).
extension PhotoStore {
  /// 벡터를 풀지 않은 비슷한 사진 행. 풀기는 actor 밖에서 한다(저장소 actor 는 직렬이라 안에서 하면 인덱서 저장·다른 읽기가 막힌다).
  struct SimilarPhotoRow: Sendable {
    let asset: ImageAsset
    let data: Data
  }

  /// `similarPhotoRows` 결과. 캐시가 있으면 푼 사진을, 없으면 풀 행과 그 시점의 캐시 세대를 준다.
  enum SimilarPhotoRead: Sendable {
    case cached([FeaturePrintedPhoto])
    case rows([SimilarPhotoRow], generation: Int)
  }

  /// 한 번에 `ids.contains` 로 고르는 식별자 수.
  private static let featurePrintFetchChunk = 1000

  func featurePrintPendingIDs() throws -> Set<ImageAsset.ID> {
    let version = ImageFeaturePrint.version
    var descriptor = FetchDescriptor<StoredImage>(
      predicate: #Predicate { image in
        !image.isScreenshot && image.creationDate != nil && !image.needsTextRecognition
          && image.textLinesData == nil && image.featurePrintVersion != version
      }
    )
    descriptor.propertiesToFetch = [\.assetID]
    return try Set(self.modelContext.fetch(descriptor).map(\.assetID))
  }

  func saveFeaturePrints(_ prints: [ImageAsset.ID: ImageFeaturePrint]) throws {
    self.invalidateSimilarPhotoCache()
    try self.write {
      let ids = Array(prints.keys)
      let stored = try self.modelContext.fetch(
        FetchDescriptor<StoredImage>(predicate: #Predicate { ids.contains($0.assetID) })
      )
      for image in stored {
        // `featurePrintPendingIDs` 와 같은 조건인 행만 바꾼다. 겹친 지난 실행이 이미 쓴 행을 덮지 않는다.
        guard Self.isFeaturePrintTarget(image),
              image.featurePrintVersion != ImageFeaturePrint.version,
              let featurePrint = prints[image.assetID]
        else {
          continue
        }
        self.setFeaturePrint(featurePrint, on: image)
      }
    }
  }

  /// 캐시(`similarPhotoCache`)가 있으면 그것을, 없으면 ① 대상이고 지금 버전 벡터가 있는 행의 메타데이터를 생성일 오름차순(같으면 식별자 순)으로
  /// 읽고 ② 시간 이웃(`SimilarPhotoGrouping.linkableIDs`)이 있는 행의 벡터만 1,000개씩 읽어 ③ ①의 순서로 이은 행(벡터 행이 없으면 뺀다)을 준다.
  /// 부르는 쪽이 행을 actor 밖에서 풀어 `cacheSimilarPhotos` 로 돌려준다. ④ 미비교 수는 같은 actor 호출 안에서 늘 새로 센다.
  func similarPhotoRows() throws -> (read: SimilarPhotoRead, uncomparedCount: Int) {
    let read: SimilarPhotoRead = if let cached = self.similarPhotoCache {
      .cached(cached)
    } else {
      try .rows(self.readSimilarPhotoRows(), generation: self.similarPhotoCacheGeneration)
    }
    let version = ImageFeaturePrint.version
    let uncompared = try self.modelContext.fetchCount(
      FetchDescriptor<StoredImage>(
        predicate: #Predicate { image in
          !image.isScreenshot && image.creationDate != nil && !image.needsTextRecognition
            && image.textLinesData == nil && image.featurePrintVersion != version
        }
      )
    )
    return (read, uncompared)
  }

  /// actor 밖에서 푼 사진을 캐시에 넣는다. 행을 읽은 뒤 캐시를 비운 쓰기가 있었으면(세대가 다르면) 넣지 않는다.
  /// 화면 Model 이 같은 배열을 받으므로 벡터 버퍼를 함께 써(복사하지 않는다) 상주 메모리가 한 벌이다.
  func cacheSimilarPhotos(_ photos: [FeaturePrintedPhoto], generation: Int) {
    if generation == self.similarPhotoCacheGeneration {
      self.similarPhotoCache = photos
    }
  }

  /// 캐시를 비우고 세대를 늘린다.
  func invalidateSimilarPhotoCache() {
    self.similarPhotoCache = nil
    self.similarPhotoCacheGeneration += 1
  }

  private func readSimilarPhotoRows() throws -> [SimilarPhotoRow] {
    let version = ImageFeaturePrint.version
    var descriptor = FetchDescriptor<StoredImage>(
      predicate: #Predicate { image in
        !image.isScreenshot && image.creationDate != nil && !image.needsTextRecognition
          && image.textLinesData == nil && image.featurePrintVersion == version
      }
    )
    descriptor.propertiesToFetch = [
      \.assetID, \.creationDate, \.latitude, \.longitude, \.pixelWidth, \.pixelHeight, \.isScreenshot,
    ]
    let assets = try self.modelContext.fetch(descriptor).map(Self.imageAsset).sorted { lhs, rhs in
      let lhsDate = lhs.creationDate ?? .distantPast
      let rhsDate = rhs.creationDate ?? .distantPast
      return lhsDate != rhsDate ? lhsDate < rhsDate : lhs.id < rhs.id
    }
    let linkable = SimilarPhotoGrouping.linkableIDs(in: assets)
    let linkableIDs = Array(linkable)
    var dataByID: [ImageAsset.ID: Data] = [:]
    for start in stride(from: 0, to: linkableIDs.count, by: Self.featurePrintFetchChunk) {
      let chunk = Array(linkableIDs[start ..< min(start + Self.featurePrintFetchChunk, linkableIDs.count)])
      var printDescriptor = FetchDescriptor<StoredFeaturePrint>(predicate: #Predicate { chunk.contains($0.assetID) })
      printDescriptor.propertiesToFetch = [\.assetID, \.data]
      for stored in try self.modelContext.fetch(printDescriptor) where dataByID[stored.assetID] == nil {
        dataByID[stored.assetID] = stored.data
      }
    }
    return assets.compactMap { asset in
      guard linkable.contains(asset.id), let data = dataByID[asset.id] else {
        return nil
      }
      return SimilarPhotoRow(asset: asset, data: data)
    }
  }

  /// 비슷한 사진 결과를 바꿀 수 있는 `save` 면 쓰기 시도 전에 캐시를 비운다(쓰기가 실패해 되돌려도 다음 읽기가 다시 맞춘다).
  /// 넘긴 이미지 중 하나라도 벡터가 있거나 벡터 대상이거나 캐시에 든 식별자면 비운다.
  /// 2단계 OCR 저장(대상 아님)처럼 그 밖의 저장은 결과를 바꾸지 않아 캐시를 둔다.
  func invalidateSimilarPhotoCache(saving images: [IndexedImage]) {
    guard let cached = self.similarPhotoCache else {
      // 캐시가 없어도 세대는 늘려, actor 밖에서 푸는 중인 결과가 이 쓰기 전의 값으로 캐시되지 않게 한다.
      self.similarPhotoCacheGeneration += 1
      return
    }
    let cachedIDs = Set(cached.map(\.id))
    let changes = images.contains { image in
      image.featurePrint != nil || cachedIDs.contains(image.id)
        || ImageFeaturePrint.isTarget(image.asset, needsTextRecognition: image.textRecognition != .notNeeded)
    }
    if changes {
      self.invalidateSimilarPhotoCache()
    }
  }

  /// 관계 행이 있으면 데이터만 바꾸고 없으면 만들어 넣는다. 버전·데이터를 같은 저장에서 함께 쓴다. nil 이면 아무것도 바꾸지 않는다.
  func setFeaturePrint(_ featurePrint: ImageFeaturePrint?, on stored: StoredImage) {
    guard let featurePrint else {
      return
    }
    if let existing = stored.featurePrint {
      existing.assetID = stored.assetID
      existing.data = featurePrint.floatData
    } else {
      let created = StoredFeaturePrint(assetID: stored.assetID, data: featurePrint.floatData)
      self.modelContext.insert(created)
      stored.featurePrint = created
    }
    stored.featurePrintVersion = ImageFeaturePrint.version
  }

  /// 벡터 대상: 스크린샷 아님·생성일 있음·OCR 대상 아님(`needsTextRecognition` 이 false 이고 줄이 없다. 옛 (false, data) 행은 읽음이라 빠진다).
  /// `featurePrintPendingIDs`·`similarPhotoRows` 의 조건과 같다.
  static func isFeaturePrintTarget(_ stored: StoredImage) -> Bool {
    !stored.isScreenshot && stored.creationDate != nil && !stored.needsTextRecognition && stored.textLinesData == nil
  }

  /// 지금 버전 벡터. 버전이 다르거나 데이터가 없거나 풀리지 않으면 nil(던지지 않는다. 파일 손상 같은 드문 경우).
  static func storedFeaturePrint(_ stored: StoredImage) -> ImageFeaturePrint? {
    guard stored.featurePrintVersion == ImageFeaturePrint.version, let data = stored.featurePrint?.data else {
      return nil
    }
    return ImageFeaturePrint(floatData: data)
  }
}
