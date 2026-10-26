#if DEBUG
  import Core
  import Foundation
  import PhotoLibraryInterface
  import PhotoLibraryTesting
  import Testing
  @testable import SampleRecorderFeature

  /// 샘플 보기: 번호 목록 → 지금 보관함 썸네일 목록, 절 전체·행별 실패, 겹친 요청과 기록·화면 닫기와의 관계.
  /// 픽스처 이미지는 (앨범 다음) 보관함 순서대로 폭이 1, 2, 3… 이라 읽은 이미지를 폭으로 구분한다.
  @MainActor
  struct SampleRecorderModelPreviewTests {
    @Test("번호 목록을 넣고 보기를 누르면 보관함을 한 번 조회해 입력 순서대로 그 번째 이미지를 썸네일로 읽어 보인다")
    func showsNumberedImages() async throws {
      let date = Date(timeIntervalSince1970: 1_700_000_000)
      let fetchCount = ValueSequence([0])
      let fixture = RecorderFixture(
        library: [.stub(id: "a", creationDate: date), .stub(id: "b"), .stub(id: "c")],
        fetchGate: { _ = fetchCount.next() }
      )

      fixture.model.sampleNumberInputChanged("3, 1")
      await fixture.model.sampleShowTapped()

      let list = try #require(fixture.model.samplePreview.list)
      #expect(list.libraryCount == 3)
      #expect(list.rows.map(\.number) == [3, 1])
      #expect(list.rows.map { $0.state.image?.cgImage.width } == [3, 1])
      #expect(list.rows.map(\.creationDate) == [nil, date])
      #expect(list.loadedCount == 2)
      #expect(list.failedCount == 0)
      #expect(fetchCount.readCount == 1)
      #expect(fixture.photoLibrary.loadImageRequests == [
        LoadImageRequest(id: "c", size: .thumbnail),
        LoadImageRequest(id: "a", size: .thumbnail),
      ])
    }

    @Test(
      "입력이 잘못됐으면 조회·읽기 없이 절 전체가 실패한다",
      arguments: [
        ("1, abc", SamplePreviewFailure.input(.invalidTokens(["abc"]))),
        (" , ", .input(.noNumbers)),
        ((1 ... 101).map(String.init).joined(separator: " "), .input(.tooMany(count: 101))),
      ]
    )
    func rejectsInvalidInput(input: String, failure: SamplePreviewFailure) async {
      let fetched = Flag()
      let fixture = RecorderFixture(library: [.stub(id: "a")], fetchGate: { fetched.set() })

      fixture.model.sampleNumberInputChanged(input)
      await fixture.model.sampleShowTapped()

      #expect(fixture.model.samplePreview.failure == failure)
      #expect(!fetched.isSet)
      #expect(fixture.photoLibrary.loadImageRequests.isEmpty)
    }

    @Test(
      "전체 접근이 아니면 읽지 않는다",
      arguments: [
        (PhotoAccessState.denied, SamplePreviewFailure.notAuthorized),
        (.notDetermined, .notAuthorized),
        (.restricted, .notAuthorized),
        (.limited, .limitedAccess),
      ]
    )
    func rejectsWithoutFullAccess(access: PhotoAccessState, failure: SamplePreviewFailure) async {
      let fixture = RecorderFixture(access: access, library: [.stub(id: "a")])

      fixture.model.sampleNumberInputChanged("1")
      await fixture.model.sampleShowTapped()

      #expect(fixture.model.samplePreview.failure == failure)
      #expect(fixture.photoLibrary.loadImageRequests.isEmpty)
    }

    @Test("보관함 장수보다 큰 번호는 그 행만 실패하고 읽지 않으며, 나머지 행은 읽는다")
    func failsOutOfRangeRow() async throws {
      let fixture = RecorderFixture(library: [.stub(id: "a"), .stub(id: "b")])

      fixture.model.sampleNumberInputChanged("1, 5, 2")
      await fixture.model.sampleShowTapped()

      let list = try #require(fixture.model.samplePreview.list)
      #expect(list.rows.map(\.state.failure) == [nil, .outOfRange, nil])
      #expect(list.rows.map { $0.state.image?.cgImage.width } == [1, nil, 2])
      #expect(list.loadedCount == 2)
      #expect(list.failedCount == 1)
      #expect(fixture.photoLibrary.loadImageRequests.map(\.id) == ["a", "b"])
    }

    @Test("빈 보관함이면 모든 행이 범위 밖이고 장수 0 을 보인다")
    func failsAllRowsOnEmptyLibrary() async throws {
      let fixture = RecorderFixture()

      fixture.model.sampleNumberInputChanged("1")
      await fixture.model.sampleShowTapped()

      let list = try #require(fixture.model.samplePreview.list)
      #expect(list.libraryCount == 0)
      #expect(list.rows.map(\.state.failure) == [.outOfRange])
      #expect(list.failedCount == 1)
      #expect(fixture.photoLibrary.loadImageRequests.isEmpty)
    }

    @Test(
      "읽기 실패는 그 행에만 이유별로 보이고 다음 행은 계속 읽는다",
      arguments: [
        (ImageLoadError.notFound, SampleRowFailure.notFound),
        (.notAvailableLocally, .notAvailableLocally),
        (.failed, .loadFailed),
      ]
    )
    func failsOnlyThatRow(error: ImageLoadError, failure: SampleRowFailure) async throws {
      let fixture = RecorderFixture(
        library: [.stub(id: "a"), .stub(id: "b"), .stub(id: "c")],
        loadErrors: ["b": error]
      )

      fixture.model.sampleNumberInputChanged("1 2 3")
      await fixture.model.sampleShowTapped()

      let list = try #require(fixture.model.samplePreview.list)
      #expect(list.rows.map(\.state.failure) == [nil, failure, nil])
      #expect(list.rows.map { $0.state.image?.cgImage.width } == [1, nil, 3])
      #expect(list.loadedCount == 2)
      #expect(list.failedCount == 1)
    }

    @Test("iCloud 대체 버전으로 읽으면 그 행 이미지에 표시가 있다")
    func marksLocalFallback() async throws {
      let fixture = RecorderFixture(library: [.stub(id: "a")], fallbackIDs: ["a"])

      fixture.model.sampleNumberInputChanged("1")
      await fixture.model.sampleShowTapped()

      let list = try #require(fixture.model.samplePreview.list)
      #expect(list.rows.first?.state.image?.isLocalFallback == true)
    }

    @Test("앞 요청이 조회 중일 때 다음 목록을 보면 앞 요청은 늦게 끝나도 버리고 읽지 않는다")
    func laterRequestWinsDuringFetch() async throws {
      let gate = FirstCallGate()
      let fixture = RecorderFixture(
        library: [.stub(id: "a"), .stub(id: "b")],
        fetchGate: { await gate.wait() }
      )
      fixture.model.sampleNumberInputChanged("1")
      let first = Task { await fixture.model.sampleShowTapped() }
      await waitUntil { gate.started.isSet }
      #expect(fixture.model.samplePreview.isFetching)

      fixture.model.sampleNumberInputChanged("2")
      await fixture.model.sampleShowTapped()
      gate.release.set()
      await first.value

      #expect(try #require(fixture.model.samplePreview.list).rows.map(\.number) == [2])
      #expect(fixture.photoLibrary.loadImageRequests == [LoadImageRequest(id: "b", size: .thumbnail)])
    }

    @Test("앞 요청이 행을 읽는 중일 때 다음 목록을 보면 앞 요청은 새 목록을 덮지 않고 남은 행도 읽지 않는다")
    func laterRequestWinsDuringRowLoad() async throws {
      let gate = FirstCallGate()
      let fixture = RecorderFixture(
        library: [.stub(id: "a"), .stub(id: "b"), .stub(id: "c")],
        // 첫 요청의 첫 행만 붙잡고, 두 번째 요청의 읽기는 바로 통과시킨다.
        loadGate: { id in
          if id == "a" {
            await gate.wait()
          }
        }
      )
      fixture.model.sampleNumberInputChanged("1, 2")
      let first = Task { await fixture.model.sampleShowTapped() }
      await waitUntil { gate.started.isSet }
      #expect(fixture.model.samplePreview.list?.rows.first?.state.isLoading == true)

      fixture.model.sampleNumberInputChanged("3")
      await fixture.model.sampleShowTapped()
      gate.release.set()
      await first.value

      let list = try #require(fixture.model.samplePreview.list)
      #expect(list.rows.map(\.number) == [3])
      #expect(list.rows.map { $0.state.image?.cgImage.width } == [3])
      #expect(fixture.photoLibrary.loadImageRequests.map(\.id) == ["a", "c"])
    }

    @Test("기록 중에는 보기를 무시한다")
    func ignoresWhileRecording() async {
      let started = Flag()
      let fixture = RecorderFixture(
        library: [.stub(id: "a")],
        classifyGate: { _ in await waitUntilCancelled(started) }
      )
      fixture.model.modeChanged(.libraryAccuracy)
      let start = Task { await fixture.model.startTapped() }
      await waitUntil { started.isSet }
      let requestCount = fixture.photoLibrary.loadImageRequests.count

      fixture.model.sampleNumberInputChanged("1")
      await fixture.model.sampleShowTapped()

      #expect(fixture.model.samplePreview.isIdle)
      #expect(fixture.photoLibrary.loadImageRequests.count == requestCount)
      fixture.model.cancelTapped()
      await start.value
    }

    @Test("보던 목록은 기록을 시작하면 닫는다")
    func startClosesList() async throws {
      let fixture = RecorderFixture(album: [.stub(id: "x")], library: [.stub(id: "a")])
      fixture.model.sampleNumberInputChanged("1")
      await fixture.model.sampleShowTapped()
      _ = try #require(fixture.model.samplePreview.list)

      await fixture.model.startTapped()

      #expect(fixture.model.samplePreview.isIdle)
    }

    @Test("조회 중에 기록을 시작하거나 화면을 닫으면 닫고, 늦게 끝나도 닫힌 채로 둔다", arguments: [true, false])
    func startOrCloseCancelsFetch(startsRecording: Bool) async {
      let gate = FirstCallGate()
      let fixture = RecorderFixture(
        album: [.stub(id: "x")],
        library: [.stub(id: "a")],
        fetchGate: { await gate.wait() }
      )
      fixture.model.sampleNumberInputChanged("1")
      let preview = Task { await fixture.model.sampleShowTapped() }
      await waitUntil { gate.started.isSet }
      #expect(fixture.model.samplePreview.isFetching)

      await self.startOrClose(fixture, startsRecording: startsRecording)
      #expect(fixture.model.samplePreview.isIdle)
      gate.release.set()
      await preview.value

      #expect(fixture.model.samplePreview.isIdle)
      #expect(!fixture.photoLibrary.loadImageRequests.contains { $0.id == "a" })
    }

    @Test("행을 읽는 중에 기록을 시작하거나 화면을 닫으면 닫고, 늦게 끝나도 닫힌 채로 두며 남은 행을 읽지 않는다", arguments: [true, false])
    func startOrCloseCancelsRowLoad(startsRecording: Bool) async {
      let gate = FirstCallGate()
      let fixture = RecorderFixture(
        album: [.stub(id: "x")],
        library: [.stub(id: "a"), .stub(id: "b")],
        loadGate: { id in
          if id == "a" {
            await gate.wait()
          }
        }
      )
      fixture.model.sampleNumberInputChanged("1, 2")
      let preview = Task { await fixture.model.sampleShowTapped() }
      await waitUntil { gate.started.isSet }

      await self.startOrClose(fixture, startsRecording: startsRecording)
      #expect(fixture.model.samplePreview.isIdle)
      gate.release.set()
      await preview.value

      #expect(fixture.model.samplePreview.isIdle)
      #expect(!fixture.photoLibrary.loadImageRequests.contains { $0.id == "b" })
    }

    @Test("번호 입력을 바꿔도 보던 목록은 그대로 둔다")
    func inputChangeKeepsList() async throws {
      let fixture = RecorderFixture(library: [.stub(id: "a")])
      fixture.model.sampleNumberInputChanged("1")
      await fixture.model.sampleShowTapped()

      fixture.model.sampleNumberInputChanged("12, 3")

      #expect(fixture.model.sampleNumberInput == "12, 3")
      let list = try #require(fixture.model.samplePreview.list)
      #expect(list.rows.map(\.number) == [1])
      #expect(list.rows.first?.state.image?.cgImage.width == 1)
    }

    private func startOrClose(_ fixture: RecorderFixture, startsRecording: Bool) async {
      if startsRecording {
        await fixture.model.startTapped()
      } else {
        fixture.model.screenDisappeared()
      }
    }
  }

  /// 첫 호출만 테스트가 풀 때까지 붙잡는다. 취소를 무시해 늦게 끝나는 요청을 흉내 낸다. 그 뒤 호출은 바로 지나간다.
  final class FirstCallGate: Sendable {
    let started = Flag()
    let release = Flag()
    private let isFirst = ValueSequence([true, false])

    func wait() async {
      guard self.isFirst.next() else { return }
      self.started.set()
      while !self.release.isSet {
        await Task.yield()
      }
    }
  }

  extension SamplePreview {
    var isIdle: Bool {
      if case .idle = self {
        return true
      }
      return false
    }

    var isFetching: Bool {
      if case .fetching = self {
        return true
      }
      return false
    }

    var list: SampleList? {
      if case let .list(list) = self {
        return list
      }
      return nil
    }

    var failure: SamplePreviewFailure? {
      if case let .failed(failure) = self {
        return failure
      }
      return nil
    }
  }

  extension SampleRowState {
    var isLoading: Bool {
      if case .loading = self {
        return true
      }
      return false
    }

    var image: AnalysisImage? {
      if case let .loaded(image) = self {
        return image
      }
      return nil
    }

    var failure: SampleRowFailure? {
      if case let .failed(failure) = self {
        return failure
      }
      return nil
    }
  }
#endif
