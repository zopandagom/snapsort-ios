#if DEBUG
  import Core
  import Foundation
  import PhotoLibraryTesting
  import Testing
  @testable import SampleRecorderFeature

  /// 기록 도구가 남기는 기기 상태(발열·저전력)와 측정 파일의 개인정보.
  @MainActor
  struct SampleRecorderModelConditionTests {
    @Test("조회 전·이미지마다·끝에 기기 상태를 읽어 발열 변화는 바뀐 곳만 남기고 상태별로 나눠 요약한다")
    func recordsThermalStateChanges() async throws {
      // 조회 전 1번, 이미지 5장, 끝 1번 읽는다.
      let states: [ThermalState] = [.nominal, .nominal, .nominal, .fair, .fair, .serious, .critical]
      let conditions = ValueSequence(states.map { DeviceConditions(thermalState: $0, isLowPowerModeEnabled: false) })
      let fixture = RecorderFixture(
        album: (0 ..< 5).map { ImageAsset.stub(id: "image-\($0)") },
        deviceConditions: { conditions.next() }
      )

      await fixture.record(.accuracy)

      let result = try #require(fixture.model.phase.result)
      #expect(result.thermalStateChanges == [
        ThermalStateChange(index: 0, state: .nominal),
        ThermalStateChange(index: 2, state: .fair),
        ThermalStateChange(index: 4, state: .serious),
      ])
      #expect(result.summary.byThermalState.nominal?.count == 2)
      #expect(result.summary.byThermalState.fair?.count == 2)
      #expect(result.summary.byThermalState.serious?.count == 1)
      let timing = try jsonObject(result.timingFile)
      #expect(timing["thermalStateAtStart"] as? String == "nominal")
      #expect(timing["thermalStateAtEnd"] as? String == "critical")
      #expect(conditions.readCount == 7)
    }

    @Test("건너뛴 이미지는 상태별 요약에서 빠지지만 발열 변화에는 남는다")
    func skippedImagesKeepThermalChanges() async throws {
      let states: [ThermalState] = [.nominal, .nominal, .nominal, .fair, .fair, .serious, .critical]
      let conditions = ValueSequence(states.map { DeviceConditions(thermalState: $0, isLowPowerModeEnabled: false) })
      let fixture = RecorderFixture(
        album: (0 ..< 5).map { ImageAsset.stub(id: "image-\($0)") },
        classifyFailures: ["image-2"],
        deviceConditions: { conditions.next() }
      )

      await fixture.record(.accuracy)

      let result = try #require(fixture.model.phase.result)
      #expect(result.thermalStateChanges.contains(ThermalStateChange(index: 2, state: .fair)))
      #expect(result.summary.byThermalState.fair?.count == 1)
    }

    @Test("이미지를 처리하기 전에 실패하면 끝값을 읽지 않고, 권한이 없으면 기기 상태를 읽지 않는다")
    func preFailureSkipsEndConditions() async {
      let albumMissing = ValueSequence([normalConditions])
      let denied = ValueSequence([normalConditions])
      let missingFixture = RecorderFixture(deviceConditions: { albumMissing.next() })
      let deniedFixture = RecorderFixture(access: .denied, deviceConditions: { denied.next() })

      await missingFixture.record(.accuracy)
      await deniedFixture.record(.accuracy)

      #expect(missingFixture.model.phase == .failed(.albumNotFound))
      #expect(albumMissing.readCount == 1)
      #expect(denied.readCount == 0)
    }

    @Test("측정 파일에 사진 식별자와 OCR 텍스트를 넣지 않는다")
    func timingFileHasNoPrivateText() async throws {
      let fixture = RecorderFixture(
        album: [.stub(id: "PRIVATE-ASSET-ID", isScreenshot: true)],
        labels: ["PRIVATE-ASSET-ID": [ImageLabel(identifier: "screenshot", confidence: 0.9)]],
        text: ["PRIVATE-ASSET-ID": ["비밀 쿠폰 번호 1234"]]
      )

      await fixture.record(.accuracy)

      let file = try #require(fixture.model.phase.result?.timingFile.file)
      let text = try #require(String(bytes: file.data, encoding: .utf8))
      #expect(!text.contains("PRIVATE-ASSET-ID"))
      #expect(!text.contains("비밀 쿠폰 번호"))
    }
  }
#endif
