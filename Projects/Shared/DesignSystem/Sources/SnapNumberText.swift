import SwiftUI

/// 숫자 글꼴: 바뀌며 굴러가는 수·줄끼리 맞추는 수(D-n·금액·순번)·따로 크게 보이는 수는 시스템 rounded 고정폭 숫자로 그린다.
/// 나눔스퀘어라운드에는 고정폭 숫자(tnum)가 없어, 수가 바뀔 때 글자 폭이 흔들리고 줄마다 자리가 어긋나 버그처럼 보이기 때문이다.
/// 문장 속에 멈춰 있는 수("사진 3장")와 날짜는 `Font.snap` 그대로 둔다.
public extension Font {
  /// 시스템 rounded + 고정폭 숫자. 굵기는 `SnapFont.Weight` 와 같은 자리로 맞춘다(R → regular, B → bold, EB → heavy).
  /// 시스템 글꼴이라 '굵은 텍스트'·Dynamic Type 을 스스로 따른다.
  static func snapNumber(_ style: Font.TextStyle, weight: SnapFont.Weight = .regular) -> Font {
    .system(style, design: .rounded, weight: weight.systemWeight).monospacedDigit()
  }

  /// 크기를 직접 정한 곳(위젯의 큰 개수)의 고정 크기 판.
  static func snapNumber(fixedSize size: CGFloat, weight: SnapFont.Weight = .regular) -> Font {
    .system(size: size, weight: weight.systemWeight, design: .rounded).monospacedDigit()
  }
}

public extension Text {
  /// 숫자 부분만 `Font.snapNumber`, 나머지는 `Font.snap` 으로 그린 글자(예: "12/300장", "곧 만료되는 기프티콘 3개").
  /// 영숫자·기호로만 된 글자("D-3", "+5", "D-day")는 통째로 숫자 글꼴이다. 조각마다 글꼴을 정하므로 바깥 `.font` 는 덮지 못한다.
  /// `snapRollingNumber` 를 붙이면 바뀐 숫자 자리만 굴러간다.
  static func snapNumbered(_ string: String, style: Font.TextStyle, weight: SnapFont.Weight = .regular) -> Text {
    self.joined(SnapNumberRuns.runs(string)) { isNumber in
      isNumber ? .snapNumber(style, weight: weight) : .snap(style, weight: weight)
    }
  }

  /// 고정 크기 판(위젯의 큰 "N개").
  static func snapNumbered(_ string: String, fixedSize size: CGFloat, weight: SnapFont.Weight = .regular) -> Text {
    self.joined(SnapNumberRuns.runs(string)) { isNumber in
      isNumber ? .snapNumber(fixedSize: size, weight: weight) : .snap(fixedSize: size, weight: weight)
    }
  }

  /// 조각마다 글꼴을 입혀 한 `Text` 로 잇는다(`Text` 끼리 `+` 는 iOS 26 에서 deprecated 라 보간으로 잇는다).
  private static func joined(_ runs: [SnapNumberRuns.Run], font: (Bool) -> Font) -> Text {
    runs.reduce(Text(verbatim: "")) { text, run in
      Text("\(text)\(Text(verbatim: run.text).font(font(run.isNumber)))")
    }
  }
}

/// 글자를 숫자 조각과 나머지 조각으로 나눈다. 숫자 조각은 숫자가 하나 이상 든 [영문·숫자 , . : / + - % 통화 기호] 의 연속이다("D-2"·"US$45.20" 이 갈라지지 않아,
/// 한글이 섞인 줄에서도 영숫자만 있는 줄과 같은 글꼴로 나온다).
enum SnapNumberRuns {
  struct Run: Equatable {
    let text: String
    let isNumber: Bool
  }

  /// U+00A0·U+202F 는 일부 지역 금액 형식이 기호와 숫자, 천 단위 사이에 넣는 공백이다(예: "12.000,50 €", "12 000,50 $US").
  private static let numberCharacters = Set("0123456789,.:/+-%$€£¥₩\u{00A0}\u{202F}")

  static func runs(_ string: String) -> [Run] {
    guard !string.isEmpty else { return [] }
    if string.allSatisfy(\.isASCII) {
      return [Run(text: string, isNumber: true)]
    }
    var runs: [Run] = []
    var current = ""
    var currentIsCandidate = false
    func flush() {
      guard !current.isEmpty else { return }
      let isNumber = currentIsCandidate && current.contains(where: \.isASCIIDigit)
      if let last = runs.last, last.isNumber == isNumber {
        runs[runs.count - 1] = Run(text: last.text + current, isNumber: isNumber)
      } else {
        runs.append(Run(text: current, isNumber: isNumber))
      }
      current = ""
    }
    for character in string {
      let isCandidate = self.numberCharacters.contains(character) || (character.isASCII && character.isLetter)
      if isCandidate != currentIsCandidate {
        flush()
        currentIsCandidate = isCandidate
      }
      current.append(character)
    }
    flush()
    return runs
  }
}

private extension Character {
  var isASCIIDigit: Bool {
    ("0" ... "9").contains(self)
  }
}

extension SnapFont.Weight {
  var systemWeight: Font.Weight {
    switch self {
    case .regular: .regular
    case .bold: .bold
    case .extraBold: .heavy
    }
  }
}
