// Debug 전용: SampleRecorderModel.swift 머리 주석 참고
#if DEBUG
  import Core
  import Foundation
  import PhotoLibraryInterface

  /// 이미지를 처리하기 전 권한·조회 단계. `SampleRecording.run` 이 처음에 부른다.
  extension SampleRecording {
    /// 권한을 확인하고 대상 이미지를 조회한다. 보관함 전체 정확도 모드는 보관함 전체를, 속도·OCR 해상도 비교 모드는 보관함 최신 N장을 고르고,
    /// 속도 모드는 인덱서처럼 보관함 전체로 여행 판정 시간을 한 번 잰다(결과는 버린다).
    /// 번호로 기록 모드는 보관함 전체를 조회해 `numbers` 번째 이미지를 입력 순서로 고르고, 보관함 장수보다 큰 번호가 있으면 실패한다.
    /// 기기 상태 시작값은 권한 확인 뒤 조회 직전에 읽는다. `deviceConditions` 는 시작값 → 이미지마다 → 끝값 순서로 부르고,
    /// 여기서 실패하면 끝값은 읽지 않는다.
    func fetchTargets(
      mode: RecordingMode,
      numbers: [Int],
      clock: ContinuousClock
    ) async -> FetchOutcome {
      let access = self.photoLibrary.accessState()
      guard access.canRead else { return .failed(.notAuthorized) }
      if mode.recordsSamples, access == .limited {
        return .failed(.limitedAccess)
      }
      let conditionsAtStart = self.deviceConditions()
      switch mode {
      case .accuracy:
        guard let album = await self.photoLibrary.fetchImageAssets(inAlbumNamed: RecordingMode.albumName) else {
          return .failed(.albumNotFound)
        }
        guard !album.isEmpty else { return .failed(.albumEmpty) }
        return .ready(RecordingRun(
          mode: mode,
          access: access,
          targets: album,
          conditionsAtStart: conditionsAtStart
        ))
      case .numberedAccuracy:
        return await self.fetchNumberedTargets(numbers, access: access, conditionsAtStart: conditionsAtStart)
      case .libraryAccuracy, .speed, .ocrResolution:
        let library = await self.photoLibrary.fetchImageAssets()
        guard !library.isEmpty else { return .failed(.noImages) }
        var run = RecordingRun(
          mode: mode,
          access: access,
          targets: mode.latestCount.map { Array(library.prefix($0)) } ?? library,
          conditionsAtStart: conditionsAtStart
        )
        run.libraryCount = library.count
        if case .speed = mode {
          let travelStart = clock.now
          _ = TravelDetector.trips(in: library, calendar: self.calendar)
          run.travelDetectionMs = travelStart.duration(to: clock.now).milliseconds
        }
        return .ready(run)
      }
    }

    /// 번호로 기록 모드: 보관함 전체를 조회해 `numbers` 번째(최신순 1부터) 이미지를 입력 순서로 고른다.
    /// 범위 밖 번호가 있으면 기록 뒤 보관함이 줄어 나머지 번호도 밀렸을 가능성이 커서 전체를 실패시킨다.
    private func fetchNumberedTargets(
      _ numbers: [Int],
      access: PhotoAccessState,
      conditionsAtStart: DeviceConditions
    ) async -> FetchOutcome {
      let library = await self.photoLibrary.fetchImageAssets()
      guard !library.isEmpty else { return .failed(.noImages) }
      let outOfRange = numbers.filter { $0 > library.count }
      guard outOfRange.isEmpty else {
        return .failed(.numbersOutOfRange(outOfRange, libraryCount: library.count))
      }
      var run = RecordingRun(
        mode: .numberedAccuracy,
        access: access,
        targets: numbers.map { library[$0 - 1] },
        conditionsAtStart: conditionsAtStart
      )
      run.libraryCount = library.count
      run.sampleNumbers = numbers
      return .ready(run)
    }
  }

  /// 이미지를 처리하기 전 권한·조회 단계의 결과.
  enum FetchOutcome {
    case ready(RecordingRun)
    case failed(RecordingFailure)
  }
#endif
