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
  static func preview(access: PhotoAccessState = .authorized) -> SampleRecorderModel {
    let album = (0 ..< 12).map { ImageAsset.stub(id: "album-\($0)", isScreenshot: $0.isMultiple(of: 2)) }
    let library = [ImageAsset].stubs(count: 300)
    var loadResults: [ImageAsset.ID: Result<AnalysisImage, ImageLoadError>] = [:]
    for asset in album + library {
      loadResults[asset.id] = .success(.stub(width: 512, height: 384))
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
      recognizeText: { _ in
        try? await Task.sleep(for: .milliseconds(40))
        return .success([
          RecognizedTextLine(text: "선물하기", confidence: 0.9, boundingBox: .zero),
          RecognizedTextLine(text: "유효기간 2026.12.31", confidence: 0.9, boundingBox: .zero),
        ])
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
