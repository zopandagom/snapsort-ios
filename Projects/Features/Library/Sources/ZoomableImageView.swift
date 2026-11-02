import Core
import ImageIO
import SwiftUI
import UIKit

/// 사진 상세 한 장의 확대 뷰 (docs/ARCHITECTURE.md §4 카테고리 화면). SwiftUI 에 이미지 확대 API 가 없어 UIKit `UIScrollView` 로 그린다.
/// 1배는 화면에 맞추고, 핀치로 원본 1:1 픽셀 이상까지 확대하며, 더블탭은 1배면 누른 곳을 중심으로 확대하고 확대 중이면 1배로 돌린다.
/// 확대는 화면 일시 상태라 Model 에 두지 않는다. 지금 장이 아니게 되거나(`isCurrent` false) 이미지가 바뀌면 1배로 되돌리고,
/// 크기만 바뀌면(아래 캡처 행동 패널 높이 변화 등) 확대를 지킨다.
/// 바깥 가로 페이저도 UIKit 스크롤 뷰라 확대 중 끌기는 이 뷰가, 1배 끌기는 페이저가 받는다.
struct ZoomableImageView: UIViewRepresentable {
  let image: AnalysisImage
  let isCurrent: Bool
  /// 확대 중인지 바뀔 때. 확대 중에는 페이저를 막는 대안(확대 중 가장자리에서 넘어가지 않을 때)을 바로 쓸 수 있게 두고, 지금은 넘기지 않는다.
  var onZoomChanged: ((Bool) -> Void)?

  func makeUIView(context _: Context) -> ZoomableScrollView {
    let view = ZoomableScrollView()
    view.configure()
    return view
  }

  func updateUIView(_ view: ZoomableScrollView, context _: Context) {
    view.onZoomChanged = self.onZoomChanged
    view.show(self.image.cgImage, orientation: self.image.orientation)
    if !self.isCurrent {
      view.resetZoom()
    }
  }

  final class ZoomableScrollView: UIScrollView, UIScrollViewDelegate {
    /// 더블탭으로 확대하는 배율. 최대 배율이 이보다 작으면 최대 배율까지.
    static let doubleTapScale: CGFloat = 2.5

    var onZoomChanged: ((Bool) -> Void)?

    private let imageView = UIImageView()
    private var image: CGImage?
    private var orientation: CGImagePropertyOrientation = .up
    /// 마지막으로 맞춘 크기. 확대·끌기로는 바뀌지 않고, 크기나 이미지가 바뀌면 다시 맞춘다.
    private var fittedBoundsSize: CGSize?
    private var isZoomed = false

    func configure() {
      self.delegate = self
      self.minimumZoomScale = 1
      self.maximumZoomScale = 1
      self.bouncesZoom = true
      self.showsHorizontalScrollIndicator = false
      self.showsVerticalScrollIndicator = false
      self.contentInsetAdjustmentBehavior = .never
      self.decelerationRate = .fast
      self.backgroundColor = .clear
      // 이미지는 장식이다(지금 장 설명은 SwiftUI 장 View 가 붙인다).
      self.imageView.isAccessibilityElement = false
      self.addSubview(self.imageView)
      let doubleTap = UITapGestureRecognizer(target: self, action: #selector(self.doubleTapped(_:)))
      doubleTap.numberOfTapsRequired = 2
      self.addGestureRecognizer(doubleTap)
    }

    /// 다른 이미지면 1배로 다시 맞춘다. 같은 이미지면 지금 확대를 둔다.
    func show(_ image: CGImage, orientation: CGImagePropertyOrientation) {
      guard image !== self.image || orientation != self.orientation else { return }
      self.image = image
      self.orientation = orientation
      self.imageView.image = UIImage(cgImage: image, scale: 1, orientation: UIImage.Orientation(orientation))
      self.fittedBoundsSize = nil
      self.setNeedsLayout()
    }

    func resetZoom() {
      guard self.zoomScale != self.minimumZoomScale else { return }
      self.setZoomScale(self.minimumZoomScale, animated: false)
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      guard self.bounds.size != self.fittedBoundsSize else { return }
      // 새 이미지(`show` 가 맞춘 크기를 지움)면 1배로, 같은 이미지에서 크기만 바뀌면(아래 패널 높이 변화 등) 확대를 지킨다.
      self.fit(keepingZoom: self.fittedBoundsSize != nil)
    }

    /// 1배에서 화면에 맞춰(aspect-fit) 가운데 둔다. 최대 배율은 원본 1:1 픽셀의 두 배, 최소 3배.
    /// `keepingZoom` 이고 확대 중이었으면 새 크기에 맞춘 뒤 같은 배율(최대 배율 안)로 보던 곳을 가운데 두고 다시 확대한다.
    private func fit(keepingZoom: Bool) {
      guard let imageSize = self.imageView.image?.size, imageSize.width > 0, imageSize.height > 0,
            self.bounds.width > 0, self.bounds.height > 0
      else { return }
      let previousScale = self.zoomScale
      // 이미지 뷰 bounds 는 확대(transform)와 상관없이 1배 크기라, 보던 곳을 그 안의 비율로 옮길 수 있다.
      let previousSize = self.imageView.bounds.size
      let previousCenter = self.convert(CGPoint(x: self.bounds.midX, y: self.bounds.midY), to: self.imageView)
      self.fittedBoundsSize = self.bounds.size
      self.zoomScale = 1
      let fitScale = min(self.bounds.width / imageSize.width, self.bounds.height / imageSize.height)
      let fitted = CGSize(width: imageSize.width * fitScale, height: imageSize.height * fitScale)
      self.imageView.frame = CGRect(origin: .zero, size: fitted)
      self.contentSize = fitted
      let fittedPixels = fitted.width * self.traitCollection.displayScale
      self.maximumZoomScale = fittedPixels > 0 ? max(3, imageSize.width / fittedPixels * 2) : 3
      self.centerContent()
      self.contentOffset = CGPoint(x: -self.contentInset.left, y: -self.contentInset.top)
      if keepingZoom, previousScale > self.minimumZoomScale + 0.01, previousSize.width > 0, previousSize.height > 0 {
        let scale = min(previousScale, self.maximumZoomScale)
        let center = CGPoint(
          x: previousCenter.x / previousSize.width * fitted.width,
          y: previousCenter.y / previousSize.height * fitted.height
        )
        let size = CGSize(width: self.bounds.width / scale, height: self.bounds.height / scale)
        self.zoom(
          to: CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
          ),
          animated: false
        )
      }
      self.zoomChanged()
    }

    /// 화면보다 작은 쪽은 inset 으로 가운데 둔다.
    private func centerContent() {
      let size = self.imageView.frame.size
      let horizontal = max(0, (self.bounds.width - size.width) / 2)
      let vertical = max(0, (self.bounds.height - size.height) / 2)
      self.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    private func zoomChanged() {
      let isZoomed = self.zoomScale > self.minimumZoomScale + 0.01
      guard isZoomed != self.isZoomed else { return }
      self.isZoomed = isZoomed
      self.onZoomChanged?(isZoomed)
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
      guard self.maximumZoomScale > self.minimumZoomScale else { return }
      if self.zoomScale > self.minimumZoomScale {
        self.setZoomScale(self.minimumZoomScale, animated: true)
        return
      }
      let scale = min(Self.doubleTapScale, self.maximumZoomScale)
      let point = recognizer.location(in: self.imageView)
      let size = CGSize(width: self.bounds.width / scale, height: self.bounds.height / scale)
      self.zoom(
        to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
        animated: true
      )
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
      self.imageView
    }

    func scrollViewDidZoom(_: UIScrollView) {
      self.centerContent()
      self.zoomChanged()
    }
  }
}

extension UIImage.Orientation {
  /// 같은 이름의 방향으로 바꾼다. 원시 값은 서로 다르므로 rawValue 로 바꾸지 않는다(`Image.Orientation` 과 같다).
  init(_ orientation: CGImagePropertyOrientation) {
    switch orientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
