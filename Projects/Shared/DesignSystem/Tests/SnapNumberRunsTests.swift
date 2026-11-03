import Testing
@testable import DesignSystem

struct SnapNumberRunsTests {
  private func run(_ text: String, _ isNumber: Bool) -> SnapNumberRuns.Run {
    SnapNumberRuns.Run(text: text, isNumber: isNumber)
  }

  @Test("영숫자·기호로만 된 글자는 통째로 숫자 조각이다")
  func asciiOnlyIsWholeNumber() {
    #expect(SnapNumberRuns.runs("D-3") == [self.run("D-3", true)])
    #expect(SnapNumberRuns.runs("D-day") == [self.run("D-day", true)])
    #expect(SnapNumberRuns.runs("+12") == [self.run("+12", true)])
  }

  @Test("한글이 섞이면 숫자가 든 숫자·기호 연속만 숫자 조각이다")
  func splitsNumbersFromHangul() {
    #expect(SnapNumberRuns.runs("12/300장") == [self.run("12/300", true), self.run("장", false)])
    #expect(SnapNumberRuns.runs("곧 만료되는 기프티콘 3개") == [
      self.run("곧 만료되는 기프티콘 ", false), self.run("3", true), self.run("개", false),
    ])
    #expect(SnapNumberRuns.runs("3일 지남") == [self.run("3", true), self.run("일 지남", false)])
    #expect(SnapNumberRuns.runs("₩12,000") == [self.run("₩12,000", true)])
  }

  @Test("숫자가 든 영문·숫자 연속은 한 조각, 숫자 없는 영문·기호는 글자 조각")
  func symbolsWithoutDigitsStayText() {
    #expect(SnapNumberRuns.runs("3개 · 가장 가까운 D-2") == [
      self.run("3", true), self.run("개 · 가장 가까운 ", false), self.run("D-2", true),
    ])
    #expect(SnapNumberRuns.runs("OCR 결과") == [self.run("OCR 결과", false)])
    // 같은 금액이 영숫자만 있는 줄("US$45.20", 통째로 숫자)과 한글이 섞인 합계 줄에서 같은 글꼴이 되게.
    #expect(SnapNumberRuns.runs("US$45.20 · 금액 모름 1장") == [
      self.run("US$45.20", true), self.run(" · 금액 모름 ", false), self.run("1", true), self.run("장", false),
    ])
    #expect(SnapNumberRuns.runs("확인 중 - 잠시만") == [self.run("확인 중 - 잠시만", false)])
    #expect(SnapNumberRuns.runs("").isEmpty)
  }
}
