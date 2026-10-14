// Debug 빌드 전용 Feature. Sources 의 모든 파일은 `#if DEBUG` 로 감싸고, App 도 `#if DEBUG` 에서만 연결한다 (docs/ARCHITECTURE.md §2).
#if DEBUG
  import Core
  import Foundation
  import ImageAnalysisInterface
  import Observation
  import PhotoLibraryInterface

  /// 실기기에서 정확도 샘플을 기록하고 분류 단계별 시간을 재고, OCR 원본 상한별 차이를 비교하는 개발 도구의 상태와 로직
  /// (docs/ARCHITECTURE.md §4 기록 도구).
  /// 측정은 메인 밖 Task(`SampleRecording`)가 하고, Model 은 진행률과 결과만 받아 상태에 반영한다.
  /// 결과 파일의 개인정보 규칙은 docs/CONVENTIONS.md §4.
  @MainActor
  @Observable
  public final class SampleRecorderModel {
    public private(set) var mode: RecordingMode = .accuracy
    public private(set) var phase: Phase = .idle

    /// 기록 중인지. 멈추는 중(`isCancelling`)도 Task 가 돌아올 때까지는 기록 중이다.
    public var isRecording: Bool {
      if case .recording = self.phase {
        return true
      }
      return false
    }

    /// 기록 중에만 있다. 멈추라는 신호를 보낼 때 쓴다.
    @ObservationIgnored private var recordingTask: Task<RecordingOutcome, Never>?
    /// 처음 받은 멈춤 이유. 기록을 시작할 때 비운다.
    @ObservationIgnored private var cancelReason: CancelReason?

    @ObservationIgnored private let recording: SampleRecording

    /// - Parameters:
    ///   - deviceConditions: 발열·저전력 모드를 읽는다. 테스트가 바꿔 넣는다.
    ///   - now: 결과 파일 이름과 기록 시각.
    ///   - calendar: 속도 모드에서 여행 판정 시간을 잴 때 쓰는 달력. 파일 이름의 시간대도 이 달력을 따른다.
    public init(
      photoLibrary: any PhotoLibraryClient,
      imageAnalysis: any ImageAnalysisClient,
      deviceConditions: @escaping @Sendable () -> DeviceConditions = DeviceConditions.current,
      now: @escaping @Sendable () -> Date = { .now },
      calendar: Calendar = .autoupdatingCurrent
    ) {
      self.recording = SampleRecording(
        photoLibrary: photoLibrary,
        imageAnalysis: imageAnalysis,
        deviceConditions: deviceConditions,
        now: now,
        calendar: calendar
      )
    }

    // MARK: - Events

    /// 기록 중에는 무시한다. 지난 결과는 그대로 남긴다.
    public func modeChanged(_ mode: RecordingMode) {
      guard !self.isRecording else { return }
      self.mode = mode
    }

    /// 기록을 시작하고 끝날 때까지 진행률을 반영한다. 기록 중에 다시 부르면 무시한다.
    /// 멈추라는 신호를 받아도 Task 가 돌아온 뒤에 돌아온다.
    public func startTapped() async {
      guard !self.isRecording else { return }
      let mode = self.mode
      // 첫 await 전에 기록 중으로 바꿔, 그사이 다시 눌러도 두 번 시작하지 않는다.
      self.cancelReason = nil
      self.phase = .recording(.starting(mode))
      let (stream, continuation) = AsyncStream.makeStream(
        of: RecordingProgress.self,
        bufferingPolicy: .bufferingNewest(1)
      )
      let task = self.recording.start(mode: mode, progress: continuation)
      self.recordingTask = task
      for await progress in stream {
        self.phase = .recording(progress.cancelling(self.cancelReason != nil))
      }
      let outcome = await task.value
      self.recordingTask = nil
      switch outcome {
      case let .failed(failure):
        self.phase = .failed(failure)
      case let .completed(result):
        // 루프가 끝난 직후에 멈춤 신호가 와도 모두 처리했으면 끝난 것으로 본다.
        self.phase = .finished(result)
      case let .cancelled(result):
        self.phase = .cancelled(result, reason: self.cancelReason ?? .user)
      }
    }

    public func cancelTapped() {
      self.cancel(.user)
    }

    /// 화면을 닫으면 측정을 멈춘다. 보관함으로 돌아가면 인덱서가 다시 돌기 때문이다.
    public func screenDisappeared() {
      self.cancel(.screenClosed)
    }

    /// 백그라운드에서는 측정 조건이 달라지므로 멈춘다.
    public func appEnteredBackground() {
      self.cancel(.background)
    }

    // MARK: - Private

    /// 기록 중이 아니면 무시한다. 처음 받은 이유만 남기고, phase 는 Task 가 돌아온 뒤 `startTapped()` 가 바꾼다.
    private func cancel(_ reason: CancelReason) {
      guard case let .recording(progress) = self.phase else { return }
      if self.cancelReason == nil {
        self.cancelReason = reason
      }
      self.recordingTask?.cancel()
      self.phase = .recording(progress.cancelling(true))
    }
  }
#endif
