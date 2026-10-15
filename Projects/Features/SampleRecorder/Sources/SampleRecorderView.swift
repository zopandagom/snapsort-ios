// Debug 전용: SampleRecorderModel.swift 머리 주석 참고
#if DEBUG
  import SwiftUI
  import UIKit

  /// Model 은 App 이 소유하고 주입한다. 닫기는 App 이 넘긴 `onClose` 로 알린다(화면 흐름은 App 이 정한다).
  public struct SampleRecorderView: View {
    let model: SampleRecorderModel
    let onClose: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    /// 공유 시트에 띄운 파일. View 전용 일시 상태다 (ARCHITECTURE §1 규칙 8).
    @State private var sharingFile: RecordedFile?

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
      .sheet(item: self.$sharingFile) { file in
        ActivityView(file: file) { self.sharingFile = nil }
          .presentationDetents([.medium, .large])
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
          Text("정확도 (보관함 전체, OCR 대상만 OCR)").tag(RecordingMode.libraryAccuracy)
          ForEach(RecordingMode.speedCounts, id: \.self) { count in
            Text("속도 (최신 \(count.formatted())장)").tag(RecordingMode.speed(count: count))
          }
          ForEach(RecordingMode.ocrResolutionCounts, id: \.self) { count in
            Text("OCR 해상도 비교 (최신 \(count.formatted())장)").tag(RecordingMode.ocrResolution(count: count))
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
      if let comparison = result.ocrComparison {
        self.ocrComparisonSection(comparison)
      }
    }

    private func filesSection(_ result: RecordingResult) -> some View {
      Section {
        if result.mode.recordsSamples {
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
          if result.mode.recordsSamples, result.samplesFile != nil {
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
        Button {
          self.sharingFile = file
        } label: {
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

  /// OCR 해상도 비교 결과 절. 타입 본문 길이 제한 때문에 확장으로 둔다.
  extension SampleRecorderView {
    private func ocrComparisonSection(_ summary: OCRResolutionSummary) -> some View {
      Section {
        LabeledContent(
          "비교",
          value: "\(summary.comparedCount)장 / OCR 대상 \(summary.targetCount)장 "
            + "(대체 버전 \(summary.fallbackCount), 건너뜀 \(summary.skippedTargetCount))"
        )
        if summary.comparedCount == 0 {
          Text("비교한 이미지가 없습니다")
        } else {
          LabeledContent(
            "기준 OCR",
            value: [
              summary.baseline.ocr.map(Self.statsText),
              "공통 합계 \(Self.secondsText(summary.baseline.commonTotalMs))",
            ]
            .compactMap(\.self)
            .joined(separator: " · ")
          )
          ForEach(summary.caps, id: \.name) { cap in
            LabeledContent(cap.name) {
              Text(Self.capText(cap, baselineCommonTotalMs: summary.baseline.commonTotalMs))
            }
          }
        }
      } header: {
        Text("OCR 해상도 비교 (기준 대비)")
      } footer: {
        Text(
          "기준(현재 상한) OCR 대비 값입니다. 낮은 상한은 기준 이미지를 줄여 만든 입력입니다. 워밍업 이미지는 시간에서 뺐습니다. "
            + "8MP·4MP 는 그보다 큰 이미지만 줄어들어 표본이 작을 수 있습니다(줄임 n장 확인)."
        )
      }
    }

    private static func capText(_ cap: OCRResolutionSummary.CapSummary, baselineCommonTotalMs: Double) -> String {
      var timing = ["OCR \(cap.ocr.map(self.statsText) ?? "-")", "공통 합계 \(self.secondsText(cap.commonTotalMs))"]
      if baselineCommonTotalMs > 0 {
        timing[1] += " (기준의 \(self.percentText(cap.commonTotalMs / baselineCommonTotalMs)))"
      }
      if let ratio = cap.timeRatio {
        timing.append("비율 p50 \(self.percentText(ratio.p50))")
      }
      var lines = [
        timing.joined(separator: " · "),
        "줄임 \(cap.downscaledCount) · 같은 입력 \(cap.sameInputCount) · 실패 \(cap.failedCount)",
        "분류 불일치 \(cap.categoryMismatchCount)/줄임 \(cap.downscaledCount)장",
      ]
      if let recall = cap.charRecall {
        lines.append(
          "재현율 합산 \(self.percentText(recall.pooled)) · 이미지 평균 \(self.percentText(recall.mean)) · "
            + "하위 5% \(self.percentText(recall.p05)) · 최저 \(self.percentText(recall.min))"
        )
      }
      lines.append(
        "날짜 놓침 \(cap.fewerDatesImageCount)/\(cap.imagesWithDatesCount)장 · "
          + "긴 숫자 놓침 \(cap.fewerLongNumbersImageCount)/\(cap.imagesWithLongNumbersCount)장"
      )
      return lines.joined(separator: "\n")
    }

    private static func secondsText(_ milliseconds: Double) -> String {
      "\((milliseconds / 1000).formatted(.number.precision(.fractionLength(1))))초"
    }

    private static func percentText(_ fraction: Double) -> String {
      fraction.formatted(.percent.precision(.fractionLength(1)))
    }
  }
#endif
