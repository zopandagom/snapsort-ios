import Core
import DesignSystem
import SwiftUI

// MARK: - 인덱싱 안내

extension LibraryView {
  /// 분석 중일 때와 멈췄을 때만 보인다. 정상으로 다 분석하면 숨기되, 미룬 이미지가 있으면 그 수는 남겨 안내한다.
  /// `isFinished` 는 미룬 수까지 더해 판단하므로, 숨기기만 하면 iCloud 에만 있는 사진처럼 분류되지 않은 이유가 사라진다.
  /// 분석 중이면 진행률의 `phase` 로 분류 중(1단계) 막대와 글자 읽는 중(2단계) 막대를 나눠 보인다. 모두 카드(`snapCard()`)로 보인다.
  /// 준비 중 카드는 로딩 점(`SnapLoadingDots`, 시스템 진행 표시처럼 읽힌다)과 문구를 보인다.
  /// 1·2단계 카드는 막대(`.snap` 스타일, 시스템 막대처럼 읽힌다) 위에 단계 그림(`SnapProgressArt`)을 둔다. 그림은 장식이라 VoiceOver 에서 읽지 않는다.
  /// 동작 줄이기면 점·그림·줄무늬가 멈춘다.
  /// 첫 진행률을 받기 전에 멈출 수도 있으므로(저장소 실패 등), 멈춤 안내는 진행률이 없어도 띄운다.
  /// 첫 진행률은 보관함과 저장소 비교를 마친 뒤에 오므로, 그 전에는 준비 중으로 보여 준다.
  /// 1·2단계 카드 아래에는 계속 처리 분류 버튼("홈으로 나가도 계속")과, 눌렀는데 시작하지 못했을 때의 안내 줄을 둔다
  /// (버튼 조건은 `LibraryModel.showsContinueInBackgroundButton`). 버튼은 나타날 때 빛이 번진다(`snapGlow()`, 동작 줄이기면 테두리만).
  /// 1·2단계 카드는 다른 분기라 단계가 바뀌면 버튼이 새로 나타나 다시 번진다(의도).
  /// 계속 처리 분류가 도는 동안(첫 분류 자동 요청이든 버튼이든)은 버튼 대신 "홈으로 나가도 이어서 분류합니다" 안내 줄을 둔다
  /// (`LibraryModel.showsContinuingInBackgroundNotice`).
  @ViewBuilder
  var indexingSection: some View {
    if self.model.isIndexingStopped {
      HStack {
        Label(self.stoppedText, systemImage: "exclamationmark.triangle")
          .font(.subheadline)
        Spacer()
        Button("다시 시도") {
          self.model.retryIndexingTapped()
        }
        .buttonStyle(.snapSecondary)
        .font(.subheadline)
      }
      .snapCard()
    } else if let progress = self.model.indexingProgress, progress.phase == .classifying {
      let doneCount = progress.indexedCount + progress.skippedCount
      self.indexingCard(continuable: true) {
        SnapProgressArt(.sorting)
          .frame(maxWidth: .infinity)
          .padding(.bottom, 8)
        ProgressView(value: Double(doneCount), total: Double(max(progress.totalCount, 1))) {
          Text("이미지 분류 중")
        } currentValueLabel: {
          Text("\(doneCount)/\(progress.totalCount)장")
        }
        .progressViewStyle(.snap(.rose))
      } footer: {
        if progress.skippedCount > 0 {
          Text("읽지 못한 \(progress.skippedCount)장은 다음에 다시 시도합니다.")
        }
        self.continueInBackgroundNotice
      }
    } else if let progress = self.model.indexingProgress, progress.phase == .recognizingText {
      // 분모는 이번 실행에서 남은 일이다. 새 사진이 대기에 더해지면 늘어난다.
      let doneCount = progress.recognizedTextCount + progress.skippedTextCount
      let totalCount = doneCount + progress.pendingTextCount
      self.indexingCard(continuable: true) {
        SnapProgressArt(.reading)
          .frame(maxWidth: .infinity)
          .padding(.bottom, 8)
        ProgressView(value: Double(doneCount), total: Double(max(totalCount, 1))) {
          Text("글자 읽는 중")
        } currentValueLabel: {
          Text("\(doneCount)/\(totalCount)장")
        }
        .progressViewStyle(.snap(.lilac))
      } footer: {
        Text("사진 분류는 끝났습니다. 기프티콘·영수증 같은 캡처는 글자를 읽으며 채웁니다.")
        if progress.skippedTextCount > 0 {
          Text("글자를 읽지 못한 \(progress.skippedTextCount)장은 다음에 다시 시도합니다.")
        }
        if progress.skippedCount > 0 {
          Text("읽지 못한 \(progress.skippedCount)장은 다음에 다시 시도합니다.")
        }
        self.continueInBackgroundNotice
      }
    } else if self.model.isIndexing {
      VStack(spacing: 14) {
        SnapLoadingDots()
        Text("이미지 분류 준비 중")
          .font(.headline)
      }
      .frame(maxWidth: .infinity)
      .snapCard()
    } else if let progress = self.model.indexingProgress, progress.skippedCount + progress.skippedTextCount > 0 {
      // 1단계·2단계 미룸은 이용자에게 같은 이유(iCloud 에만 있거나 읽을 수 없음)라 합쳐 센다.
      self.indexingCard {
        Label(
          "읽지 못한 \(progress.skippedCount + progress.skippedTextCount)장은 다음에 다시 시도합니다",
          systemImage: "icloud.slash"
        )
        .font(.subheadline)
      } footer: {
        Text("iCloud 에만 있거나 읽을 수 없는 사진입니다.")
      }
    }
  }

  /// 인덱싱 안내 카드. 목록 섹션의 footer 였던 안내는 카드 안 아래에 작은 보조 글자로 둔다.
  /// `continuable` 이면 footer 아래에 계속 처리 분류 버튼이나, 계속 처리 분류가 도는 동안의 안내 줄 자리를 둔다(보일 조건은 Model).
  private func indexingCard(
    continuable: Bool = false,
    @ViewBuilder content: () -> some View,
    @ViewBuilder footer: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      content()
      VStack(alignment: .leading, spacing: 4) {
        footer()
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
      if continuable, self.model.showsContinueInBackgroundButton {
        Button {
          self.model.continueInBackgroundTapped()
        } label: {
          Label("홈으로 나가도 계속", systemImage: "house")
        }
        .buttonStyle(.snapSecondary)
        .font(.subheadline)
        .snapGlow()
        .padding(.top, 4)
      } else if continuable, self.model.showsContinuingInBackgroundNotice {
        Label("홈으로 나가도 이어서 분류합니다", systemImage: "house")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .snapCard()
  }

  /// 계속 처리 분류를 눌렀는데 시작하지 못했을 때의 안내(footer 보조 글자). 카드 문구처럼 "~합니다" 체로 쓴다.
  @ViewBuilder
  private var continueInBackgroundNotice: some View {
    switch self.model.continuedIndexingNotice {
    case .tryLater:
      Text("지금은 시작할 수 없습니다. 잠시 뒤 다시 눌러 주세요.")
    case .unavailable:
      Text("이 기기에서는 앱을 열어 둔 동안 분류하고, 홈으로 나가면 충전 중에 이어서 분류합니다.")
    case nil:
      EmptyView()
    }
  }

  /// 멈춘 단계로 고른다. 다 분석한 뒤 증분 반영 중에 멈추면 마지막 진행률이 n/n 이므로, 개수 대신 새 사진을 분류하지 못했다고 안내한다.
  var stoppedText: String {
    guard let progress = self.model.indexingProgress else { return "분류를 마치지 못했습니다" }
    switch progress.phase {
    case .classifying:
      return "분류를 마치지 못했습니다 (\(progress.indexedCount + progress.skippedCount)/\(progress.totalCount))"
    case .recognizingText:
      return "글자 읽기를 마치지 못했습니다 (남은 \(progress.pendingTextCount)장)"
    case .finished:
      return "새 사진을 분류하지 못했습니다"
    }
  }
}
