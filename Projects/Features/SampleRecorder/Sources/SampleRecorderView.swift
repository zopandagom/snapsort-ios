// Debug 전용: SampleRecorderModel.swift 머리 주석 참고
#if DEBUG
  import SwiftUI
  import UIKit

  /// Model 은 App 이 소유하고 주입한다. 닫기는 App 이 넘긴 `onClose` 로 알린다(화면 흐름은 App 이 정한다).
  public struct SampleRecorderView: View {
    let model: SampleRecorderModel
    let onClose: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    public init(model: SampleRecorderModel, onClose: @escaping () -> Void) {
      self.model = model
      self.onClose = onClose
    }

    public var body: some View {
      NavigationStack {
        List {
          self.modeSection
          self.controlSection
          self.phaseSection
        }
        .navigationTitle("기록")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("닫기", action: self.onClose)
          }
        }
      }
      // 기록 화면을 떠나면 자동 잠금을 되돌린다(규칙 8: 화면을 떠나면 되돌리는 설정).
      .onDisappear {
        self.model.screenDisappeared()
        UIApplication.shared.isIdleTimerDisabled = false
      }
      .onChange(of: self.scenePhase) { _, phase in
        if phase == .background {
          self.model.appEnteredBackground()
        }
      }
      // 긴 측정 중 자동 잠금으로 앱이 백그라운드에 가면 측정이 취소되므로 기록 중에만 끈다. 화면에만 걸린 효과라 View 가 맡는다(ARCHITECTURE §1 단방향 규칙 8).
      .onChange(of: self.model.isRecording) { _, isRecording in
        UIApplication.shared.isIdleTimerDisabled = isRecording
      }
    }

    private var modeSection: some View {
      Section {
        Picker(
          "모드",
          selection: Binding(get: { self.model.mode }, set: { self.model.modeChanged($0) })
        ) {
          Text("정확도 (앨범 '\(RecordingMode.albumName)')").tag(RecordingMode.accuracy)
          ForEach(RecordingMode.speedCounts, id: \.self) { count in
            Text("속도 (최신 \(count.formatted())장)").tag(RecordingMode.speed(count: count))
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
        .disabled(self.model.isRecording)
      } header: {
        Text("모드")
      }
    }

    private var controlSection: some View {
      Section {
        if case let .recording(progress) = self.model.phase {
          if progress.isCancelling {
            HStack(spacing: 12) {
              ProgressView()
              Text("멈추는 중…")
            }
          } else {
            Button("멈추기", role: .destructive) {
              self.model.cancelTapped()
            }
          }
        } else {
          Button("기록 시작") {
            Task { await self.model.startTapped() }
          }
        }
      }
    }

    @ViewBuilder
    private var phaseSection: some View {
      switch self.model.phase {
      case .idle:
        EmptyView()
      case let .recording(progress):
        Section {
          ProgressView(value: Double(progress.processed), total: Double(max(progress.total, 1))) {
            Text(progress.total == 0 ? "이미지 조회 중" : "기록 중")
          } currentValueLabel: {
            Text("\(progress.processed)/\(progress.total), 건너뜀 \(progress.skipped), 대체 버전 \(progress.fallbackCount)")
          }
        }
      case let .finished(result):
        self.resultSections(result, status: nil)
      case let .cancelled(result, reason):
        self.resultSections(result, status: self.cancelText(reason))
      case let .failed(failure):
        Section {
          Label(self.failureText(failure), systemImage: "exclamationmark.triangle")
        }
      }
    }

    @ViewBuilder
    private func resultSections(_ result: RecordingResult, status: String?) -> some View {
      if let status {
        Section {
          Label(status, systemImage: "stop.circle")
        }
      }
      self.filesSection(result)
      self.summarySection(result)
    }

    private func filesSection(_ result: RecordingResult) -> some View {
      Section {
        if result.mode == .accuracy {
          if let samplesFile = result.samplesFile {
            self.fileRow(samplesFile, title: "샘플 초안 \(result.recordedSampleCount)장")
          } else {
            Text("기록한 샘플이 없습니다")
          }
        }
        self.fileRow(result.timingFile, title: "측정")
      } header: {
        Text("결과 파일")
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          if result.mode == .accuracy, result.samplesFile != nil {
            Text("OCR 텍스트가 들어 있습니다. AirDrop 이나 '파일에 저장'의 '나의 iPhone' 위치로만 옮기세요.")
          }
          if result.fallbackCount > 0 {
            Text(
              "iCloud 대체 버전으로 읽은 이미지 \(result.fallbackCount)장. 정확도 샘플은 사진 앱에서 원본을 기기에 받아 둔 뒤 기록하세요."
            )
          }
        }
      }
    }

    @ViewBuilder
    private func fileRow(_ output: FileOutput, title: String) -> some View {
      switch output {
      case let .ready(file):
        ShareLink(item: file, preview: SharePreview(file.fileName)) {
          Label(title, systemImage: "square.and.arrow.up")
        }
      case .encodingFailed:
        LabeledContent(title, value: "파일을 만들지 못했습니다")
      }
    }

    private func summarySection(_ result: RecordingResult) -> some View {
      let summary = result.summary
      let stages: [(String, Stats?)] = [
        ("썸네일 로드", summary.thumbnailLoad),
        ("분류", summary.classify),
        ("원본 로드", summary.largestLoad),
        ("OCR", summary.ocr),
        ("pipeline", summary.pipeline),
        ("한 장 전체", summary.total),
      ]
      return Section {
        ForEach(stages, id: \.0) { title, stats in
          if let stats {
            LabeledContent(title, value: Self.statsText(stats))
          }
        }
        LabeledContent("전체 시간", value: "\(result.totalSeconds.formatted(.number.precision(.fractionLength(1))))초")
        if let firstImageMs = summary.firstImagePipelineMs {
          LabeledContent("첫 이미지 pipeline", value: Self.msText(firstImageMs))
        }
        if let ratio = summary.ocrTargetRatio {
          LabeledContent(
            "OCR 대상",
            value: "\(summary.ocrTargetCount)장 (\(ratio.formatted(.percent.precision(.fractionLength(1)))))"
          )
        }
        LabeledContent("발열 상태", value: result.thermalStateChanges.map(\.state.rawValue).joined(separator: " → "))
        ForEach(ThermalState.allCases, id: \.self) { state in
          if let stats = summary.byThermalState[state] {
            LabeledContent("pipeline (\(state.rawValue))", value: Self.statsText(stats))
          }
        }
        LabeledContent(
          "저전력 모드",
          value: "\(Self.onOff(result.conditionsAtStart.isLowPowerModeEnabled)) → "
            + Self.onOff(result.conditionsAtEnd.isLowPowerModeEnabled)
        )
        ForEach(SkippedImage.Reason.allCases, id: \.self) { reason in
          let count = result.skipped.count { $0.reason == reason }
          if count > 0 {
            LabeledContent("건너뜀 (\(self.skipText(reason)))", value: "\(count)장")
          }
        }
      } header: {
        Text("요약 (평균 / p50 / p95 / 최대)")
      }
    }

    private static func statsText(_ stats: Stats) -> String {
      [stats.meanMs, stats.p50Ms, stats.p95Ms, stats.maxMs].map(self.msText).joined(separator: " / ")
    }

    private static func msText(_ milliseconds: Double) -> String {
      "\(milliseconds.formatted(.number.precision(.fractionLength(0))))ms"
    }

    private static func onOff(_ isOn: Bool) -> String {
      isOn ? "켬" : "끔"
    }

    private func skipText(_ reason: SkippedImage.Reason) -> String {
      switch reason {
      case .unavailable: "읽지 못함"
      case .gone: "보관함에 없음"
      case .analysisFailed: "분석 실패"
      }
    }

    private func failureText(_ failure: RecordingFailure) -> String {
      switch failure {
      case .notAuthorized: "사진을 읽을 권한이 없습니다"
      case .limitedAccess: "정확도 기록은 전체 사진 접근에서만 됩니다. 설정에서 전체 접근을 허용하세요"
      case .albumNotFound: "사진 앱에 '\(RecordingMode.albumName)' 앨범을 만들어 샘플 이미지를 넣으세요"
      case .albumEmpty: "'\(RecordingMode.albumName)' 앨범이 비어 있습니다"
      case .noImages: "보관함에 이미지가 없습니다"
      }
    }

    private func cancelText(_ reason: CancelReason) -> String {
      switch reason {
      case .user: "멈췄습니다"
      case .background: "앱이 백그라운드로 가서 멈췄습니다"
      case .screenClosed: "화면을 닫아 멈췄습니다"
      }
    }
  }
#endif
