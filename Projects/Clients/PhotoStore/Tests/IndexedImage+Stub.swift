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
    categories: Set<ImageCategory> = [],
    gifticon: GifticonInfo? = nil,
    gifticonModelFill: GifticonModelFill = .pending(failures: 0),
    receipt: ReceiptInfo? = nil,
    captureGroups: CaptureGroups? = nil,
    isScreenshot: Bool = false
  ) -> IndexedImage {
    IndexedImage(
      asset: ImageAsset(
        id: id,
        creationDate: creationDate,
        coordinate: coordinate,
        pixelWidth: 1170,
        pixelHeight: 2532,
        isScreenshot: isScreenshot
      ),
      labels: labels,
      textRecognition: textRecognition,
      categories: categories,
      gifticon: gifticon,
      gifticonModelFill: gifticonModelFill,
      receipt: receipt,
      captureGroups: captureGroups
    )
  }
}
