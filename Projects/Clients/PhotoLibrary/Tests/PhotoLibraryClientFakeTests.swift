import Core
import PhotoLibraryInterface
import PhotoLibraryTesting
import Synchronization
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

  @Test("앨범 제목으로 정해 둔 이미지를 돌려주고, 없는 제목은 nil 이다")
  func fetchesAlbum() async {
    let fake = PhotoLibraryClientFake(albums: ["샘플": [.stub(id: "b"), .stub(id: "a")]])

    #expect(await fake.fetchImageAssets(inAlbumNamed: "샘플")?.map(\.id) == ["b", "a"])
    #expect(await fake.fetchImageAssets(inAlbumNamed: "없음") == nil)
  }

  @Test("조회 대기를 주면 두 조회 모두 대기가 풀린 뒤에 결과를 준다")
  func waitsForFetchGate() async {
    let (signal, release) = AsyncStream.makeStream(of: Void.self)
    // 여러 조회가 함께 기다리도록 스트림은 한 Task 만 읽고, 조회는 그 Task 를 기다린다.
    let released = Task { for await _ in signal {} }
    let waitingCount = Mutex(0)
    let fake = PhotoLibraryClientFake(
      imageAssets: [.stub(id: "a")],
      albums: ["샘플": [.stub(id: "b")]],
      fetchGate: {
        waitingCount.withLock { $0 += 1 }
        await released.value
      }
    )

    let fetches = Task {
      async let library = fake.fetchImageAssets()
      async let album = fake.fetchImageAssets(inAlbumNamed: "샘플")
      return await (library.map(\.id), album?.map(\.id))
    }
    while waitingCount.withLock({ $0 }) < 2 {
      await Task.yield()
    }
    release.finish()
    let (library, album) = await fetches.value

    #expect(library == ["a"])
    #expect(album == ["b"])
  }
}
