import ClassifierInterface
import Foundation
import ImageAnalysisInterface
import PhotoLibraryInterface
import PhotoStoreInterface

/// 실행(`IndexingRun`)을 만드는 의존성. `IndexingClientImpl` 이 초기화를 마치기 전에 실행기(`IndexingExecutor`)에 넘기려고 따로 둔다.
struct IndexingRunFactory: Sendable {
  let photoLibrary: any PhotoLibraryClient
  let imageAnalysis: any ImageAnalysisClient
  let photoStore: any PhotoStoreClient
  let classifier: any ClassifierClient
  let calendar: Calendar
  let batchSize: Int
  let textBatchSize: Int

  func makeRun(gate: StoreGate, environment: RunEnvironment) -> IndexingRun {
    IndexingRun(
      photoLibrary: self.photoLibrary,
      imageAnalysis: self.imageAnalysis,
      photoStore: self.photoStore,
      classifier: self.classifier,
      calendar: self.calendar,
      batchSize: self.batchSize,
      textBatchSize: self.textBatchSize,
      gate: gate,
      environment: environment
    )
  }
}
