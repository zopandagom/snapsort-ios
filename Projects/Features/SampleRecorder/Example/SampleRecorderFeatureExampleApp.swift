import Core
import CoreGraphics
import ImageAnalysisInterface
import ImageAnalysisTesting
import PhotoLibraryInterface
import PhotoLibraryTesting
import SampleRecorderFeature
import SwiftUI

/// 실제 사진 없이 기록 화면을 확인하는 데모 앱. Preview 도 여기에 둔다.
/// 기록 도구가 Debug 전용이라 이 앱도 Debug 로만 빌드한다.
@main
struct SampleRecorderFeatureExampleApp: App {
  @State private var model = SampleRecorderModel.preview()

  var body: some Scene {
    WindowGroup {
      SampleRecorderView(model: self.model) {}
    }
  }
}

extension SampleRecorderModel {
  /// 앨범 샘플 12장과 보관함 300장. 분석마다 조금 기다려 진행률이 보이게 하고, 한 장은 iCloud 에만 있어 건너뛴다.
  /// OCR 해상도 비교 절이 보이도록 보관함 10장마다 한 장은 6MP(3000×2000)로 읽히고, OCR 은 그 이미지를 1.5MP 미만으로 줄인 입력에서 날짜 줄을 놓친다.
  static func preview(access: PhotoAccessState = .authorized) -> SampleRecorderModel {
    let album = (0 ..< 12).map { ImageAsset.stub(id: "album-\($0)", isScreenshot: $0.isMultiple(of: 2)) }
    let library = [ImageAsset].stubs(count: 300)
    var loadResults: [ImageAsset.ID: Result<AnalysisImage, ImageLoadError>] = [:]
    // 큰 이미지는 한 장을 함께 써 메모리를 아낀다.
    let large = AnalysisImage.stub(width: 3000, height: 2000)
    for asset in album + library {
      loadResults[asset.id] = .success(.stub(width: 512, height: 384))
    }
    for (offset, asset) in library.enumerated() where offset.isMultiple(of: 10) {
      loadResults[asset.id] = .success(large)
    }
    loadResults["album-3"] = .failure(.notAvailableLocally)
    let photoLibrary = PhotoLibraryClientFake(
      currentState: access,
      imageAssets: library,
      loadImageResults: loadResults,
      albums: [RecordingMode.albumName: album]
    )
    let imageAnalysis = ImageAnalysisClientFake(
      classify: { _ in
        try? await Task.sleep(for: .milliseconds(20))
        return .success([
          ImageLabel(identifier: "screenshot", confidence: 0.91),
          ImageLabel(identifier: "drink", confidence: 0.04),
        ])
      },
      recognizeText: { image in
        try? await Task.sleep(for: .milliseconds(40))
        let lines = [
          RecognizedTextLine(text: "선물하기", confidence: 0.9, boundingBox: .zero),
          RecognizedTextLine(text: "유효기간 2026.12.31", confidence: 0.9, boundingBox: .zero),
        ]
        // 큰 이미지를 1.5MP 미만으로 줄인 입력만 날짜 줄을 놓친다. 512×384 이미지는 다른 모드처럼 두 줄을 준다.
        let (width, height) = (image.cgImage.width, image.cgImage.height)
        return .success(width > 512 && width * height < 1_500_000 ? Array(lines.prefix(1)) : lines)
      }
    )
    return SampleRecorderModel(photoLibrary: photoLibrary, imageAnalysis: imageAnalysis)
  }
}

#Preview("전체 접근") {
  SampleRecorderView(model: .preview()) {}
}

#Preview("제한 접근") {
  SampleRecorderView(model: .preview(access: .limited)) {}
}
