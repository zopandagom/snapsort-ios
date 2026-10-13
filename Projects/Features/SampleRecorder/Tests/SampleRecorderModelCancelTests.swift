#if DEBUG
  import Core
  import Foundation
  import PhotoLibraryTesting
  import Testing
  @testable import SampleRecorderFeature

  /// 기록 도구의 멈춤·재진입과 기록 중이 아닐 때의 이벤트. 분석이나 조회를 Fake 에서 붙잡아 둔 채 이벤트를 보낸다.
  @MainActor
  struct SampleRecorderModelCancelTests {
    @Test("분석 도중 멈추면 startTapped 가 돌아오고, 이미 끝난 이미지만 부분 결과로 남긴다")
    func cancelsDuringAnalysis() async throws {
      let started = Flag()
      let fixture = RecorderFixture(
        album: [.stub(id: "a"), .stub(id: "b"), .stub(id: "c")],
        classifyGate: { id in
          if id == "b" {
            await waitUntilCancelled(started)
          }
        }
      )
      fixture.model.modeChanged(.accuracy)
      let start = Task { await fixture.model.startTapped() }
      await waitUntil { started.isSet }

      fixture.model.cancelTapped()
      await start.value

      #expect(fixture.model.phase.cancelReason == .user)
      let result = try #require(fixture.model.phase.result)
      #expect(try jsonArray(result.samplesFile).map { $0["name"] as? String } == ["앨범 001"])
      let timing = try jsonObject(result.timingFile)
      #expect(timing["processedCount"] as? Int == 1)
      #expect(timing["thermalStateAtEnd"] as? String == "nominal")
      #expect(!fixture.photoLibrary.loadImageRequests.contains { $0.id == "c" })
    }

    @Test(
      "화면을 닫거나 백그라운드로 가면 멈추고 그 이유를 보인다",
      arguments: [CancelReason.screenClosed, .background]
    )
    func cancelsForScreenAndBackground(reason: CancelReason) async {
      let started = Flag()
      let fixture = RecorderFixture(
        album: [.stub(id: "a")],
        classifyGate: { _ in await waitUntilCancelled(started) }
      )
      let start = Task { await fixture.model.startTapped() }
      await waitUntil { started.isSet }

      if reason == .screenClosed {
        fixture.model.screenDisappeared()
      } else {
        fixture.model.appEnteredBackground()
      }
      await start.value

      #expect(fixture.model.phase.cancelReason == reason)
    }

    @Test("조회 도중 멈추면 이미지 0장의 부분 결과로 끝나고, 발열 변화 없이 시작값과 끝값만 남긴다")
    func cancelsDuringFetch() async throws {
      let started = Flag()
      let conditions = ValueSequence([normalConditions])
      let fixture = RecorderFixture(
        album: [.stub(id: "a")],
        fetchGate: { await waitUntilCancelled(started) },
        deviceConditions: { conditions.next() }
      )
      let start = Task { await fixture.model.startTapped() }
      await waitUntil { started.isSet }

      fixture.model.cancelTapped()
      await start.value

      #expect(fixture.model.phase.cancelReason == .user)
      let timing = try jsonObject(fixture.model.phase.result?.timingFile)
      #expect(timing["processedCount"] as? Int == 0)
      #expect((timing["thermalStateChanges"] as? [Any])?.isEmpty == true)
      let summary = try #require(timing["summary"] as? [String: Any])
      #expect((summary["byThermalState"] as? [String: Any])?.isEmpty == true)
      #expect(timing["thermalStateAtStart"] as? String == "nominal")
      #expect(timing["thermalStateAtEnd"] as? String == "nominal")
      #expect(conditions.readCount == 2)
      #expect(fixture.photoLibrary.loadImageRequests.isEmpty)
    }

    @Test("멈추는 중임을 보이고, 처음 받은 멈춤 이유를 남긴다")
    func keepsFirstCancelReason() async {
      let started = Flag()
      let fixture = RecorderFixture(
        album: [.stub(id: "a")],
        classifyGate: { _ in await waitUntilCancelled(started) }
      )
      let start = Task { await fixture.model.startTapped() }
      await waitUntil { started.isSet }

      fixture.model.cancelTapped()
      guard case let .recording(progress) = fixture.model.phase else {
        Issue.record("멈추는 동안에도 기록 중이어야 한다")
        return
      }
      #expect(progress.isCancelling)
      fixture.model.appEnteredBackground()
      fixture.model.screenDisappeared()
      await start.value

      #expect(fixture.model.phase.cancelReason == .user)
    }

    // MARK: - 재진입·기록 중이 아닐 때

    @Test("기록 중에 다시 시작해도 한 번만 기록하고, 끝난 뒤 다시 시작하면 새 결과로 바뀐다")
    func ignoresReentrantStart() async throws {
      let dates = ValueSequence([
        Date(timeIntervalSince1970: 1_800_000_000),
        Date(timeIntervalSince1970: 1_800_003_600),
      ])
      let fixture = RecorderFixture(album: [.stub(id: "a")], now: { dates.next() })
      let first = Task { await fixture.model.startTapped() }
      await fixture.model.startTapped()
      await first.value

      #expect(fixture.photoLibrary.loadImageRequests.count == 2)
      let firstName = try #require(fixture.model.phase.result?.timingFile.file?.fileName)

      await fixture.model.startTapped()

      #expect(fixture.photoLibrary.loadImageRequests.count == 4)
      let secondName = try #require(fixture.model.phase.result?.timingFile.file?.fileName)
      #expect(firstName != secondName)
    }

    @Test("기록 중이 아니면 모드만 바꾸고, 멈춤 이벤트는 아무것도 바꾸지 않는다")
    func eventsWhileNotRecording() async {
      let fixture = RecorderFixture(album: [.stub(id: "a")], library: .stubs(count: 1))
      let model = fixture.model

      model.cancelTapped()
      model.screenDisappeared()
      model.appEnteredBackground()
      #expect(model.phase == .idle)
      model.modeChanged(.speed(count: 1000))
      #expect(model.mode == .speed(count: 1000))

      await fixture.record(.accuracy)
      let finished = model.phase
      model.cancelTapped()
      model.screenDisappeared()
      model.appEnteredBackground()
      #expect(model.phase == finished)
      model.modeChanged(.speed(count: 100))
      #expect(model.mode == .speed(count: 100))
      // 지난 결과는 남는다.
      #expect(model.phase == finished)

      let failing = RecorderFixture(access: .denied)
      await failing.record(.accuracy)
      failing.model.cancelTapped()
      #expect(failing.model.phase == .failed(.notAuthorized))
    }

    @Test("기록 중에는 모드를 바꾸지 않는다")
    func ignoresModeChangeWhileRecording() async {
      let started = Flag()
      let fixture = RecorderFixture(
        album: [.stub(id: "a")],
        classifyGate: { _ in await waitUntilCancelled(started) }
      )
      let start = Task { await fixture.model.startTapped() }
      await waitUntil { started.isSet }

      fixture.model.modeChanged(.speed(count: 100))
      #expect(fixture.model.mode == .accuracy)

      fixture.model.cancelTapped()
      await start.value
    }
  }
#endif
