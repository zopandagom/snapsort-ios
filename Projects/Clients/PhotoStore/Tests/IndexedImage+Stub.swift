import Core
import Foundation
import PhotoStoreInterface

extension IndexedImage {
  static func stub(
    id: String,
    creationDate: Date? = nil,
    coordinate: Coordinate? = nil,
    labels: [ImageLabel] = [],
    textRecognition: TextRecognition = .notNeeded,
    categories: Set<ImageCategory> = []
  ) -> IndexedImage {
    IndexedImage(
      asset: ImageAsset(
        id: id,
        creationDate: creationDate,
        coordinate: coordinate,
        pixelWidth: 1170,
        pixelHeight: 2532,
        isScreenshot: false
      ),
      labels: labels,
      textRecognition: textRecognition,
      categories: categories
    )
  }
}
