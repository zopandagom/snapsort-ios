import Core
import PhotoLibraryInterface
import PhotoLibraryTesting
import Testing

struct PhotoLibraryClientFakeTests {
  @Test("정해 둔 이미지를 크기와 관계없이 돌려주고 요청을 순서대로 기록한다")
  func loadsConfiguredImage() async throws {
    let image = AnalysisImage.stub(width: 8, height: 6, orientation: .right)
    let fake = PhotoLibraryClientFake(loadImageResults: ["a": .success(image)])

    let thumbnail = try await fake.loadImage(id: "a", size: .thumbnail)
    let largest = try await fake.loadImage(id: "a", size: .largestAvailable)

    #expect(thumbnail.cgImage.width == 8)
    #expect(thumbnail.orientation == .right)
    #expect(largest.cgImage.height == 6)
    #expect(fake.loadImageRequests == [
      LoadImageRequest(id: "a", size: .thumbnail),
      LoadImageRequest(id: "a", size: .largestAvailable),
    ])
  }

  @Test("정해 둔 실패를 던진다")
  func throwsConfiguredError() async {
    let fake = PhotoLibraryClientFake(loadImageResults: ["cloud": .failure(.notAvailableLocally)])

    await #expect(throws: ImageLoadError.notAvailableLocally) {
      try await fake.loadImage(id: "cloud", size: .largestAvailable)
    }
  }

  @Test("정해 두지 않은 식별자는 보관함에 없는 것으로 본다")
  func throwsNotFoundForUnknownID() async {
    let fake = PhotoLibraryClientFake()

    await #expect(throws: ImageLoadError.notFound) {
      try await fake.loadImage(id: "missing", size: .thumbnail)
    }
    #expect(fake.loadImageRequests == [LoadImageRequest(id: "missing", size: .thumbnail)])
  }

  @Test("취소된 Task 에는 정해 둔 결과 대신 취소를 던진다")
  func throwsCancelledWhenTaskCancelled() async {
    let fake = PhotoLibraryClientFake(loadImageResults: ["a": .success(.stub())])

    // Task 에 typed throws 클로저를 넘기면 런타임이 타입을 풀지 못해 테스트가 멈추므로, 오류를 값으로 돌려받는다.
    let task = Task { () -> ImageLoadError? in
      withUnsafeCurrentTask { $0?.cancel() }
      do throws(ImageLoadError) {
        _ = try await fake.loadImage(id: "a", size: .thumbnail)
        return nil
      } catch {
        return error
      }
    }

    #expect(await task.value == .cancelled)
  }
}
