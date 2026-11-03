import CoreText
import DesignSystem
import SwiftUI
import Testing
import UIKit

@MainActor
struct SnapFontTests {
  private let postScriptNames = ["NanumSquareRoundOTFR", "NanumSquareRoundOTFB", "NanumSquareRoundOTFEB"]

  @Test("글꼴을 처음 쓰면 R·B·EB 세 굵기가 등록되고 한글 글리프가 있다")
  func registersAllWeightsWithHangul() throws {
    _ = Font.snap(.headline, weight: .bold)
    for name in self.postScriptNames {
      let font = try #require(UIFont(name: name, size: 17), "등록되지 않음: \(name)")
      let characters = Array("간직함".utf16)
      var glyphs = [CGGlyph](repeating: 0, count: characters.count)
      #expect(CTFontGetGlyphsForCharacters(font as CTFont, characters, &glyphs, characters.count))
    }
  }

  @Test("내비게이션 바 큰 제목은 EB, 작은 제목은 B 이고 Dynamic Type 크기를 따른다")
  func navigationBarUsesRoundedHangul() throws {
    SnapNavigationBar.applyRoundedTitles()
    let bar = UINavigationBar.appearance()
    let large = try #require(bar.largeTitleTextAttributes?[.font] as? UIFont)
    let inline = try #require(bar.titleTextAttributes?[.font] as? UIFont)
    #expect(large.fontName == "NanumSquareRoundOTFEB")
    #expect(inline.fontName == "NanumSquareRoundOTFB")
    #expect(large.pointSize == UIFont.preferredFont(forTextStyle: .largeTitle).pointSize)
    #expect(inline.pointSize == UIFont.preferredFont(forTextStyle: .headline).pointSize)
  }

  @Test("굵은 텍스트가 켜져 있으면 한 단계 굵게, EB 는 그대로")
  func boldTextStepsUpOneWeight() {
    #expect(SnapFont.Weight.regular.resolved(boldText: true) == .bold)
    #expect(SnapFont.Weight.bold.resolved(boldText: true) == .extraBold)
    #expect(SnapFont.Weight.extraBold.resolved(boldText: true) == .extraBold)
    for weight in SnapFont.Weight.allCases {
      #expect(weight.resolved(boldText: false) == weight)
    }
  }

  @Test("툴바 글자 버튼과 검색창 글자는 R 이다")
  func barButtonsAndSearchFieldUseRegular() throws {
    SnapNavigationBar.applyRoundedTitles()
    for state in [UIControl.State.normal, .highlighted, .disabled] {
      let font = try #require(UIBarButtonItem.appearance().titleTextAttributes(for: state)?[.font] as? UIFont)
      #expect(font.fontName == "NanumSquareRoundOTFR")
    }
    let search = try #require(UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).font)
    #expect(search.fontName == "NanumSquareRoundOTFR")
  }

  @Test("글꼴 라이선스 전문(OFL)이 글꼴과 같은 번들에 들어 있다")
  func bundlesLicense() throws {
    _ = Font.snap(.headline, weight: .bold)
    let font = try #require(UIFont(name: "NanumSquareRoundOTFB", size: 17))
    let fontURL = try #require(CTFontCopyAttribute(font as CTFont, kCTFontURLAttribute) as? URL)
    let license = fontURL.deletingLastPathComponent().appendingPathComponent("OFL.txt")
    let text = try String(contentsOf: license, encoding: .utf8)
    #expect(text.contains("NanumSquareRound"))
    #expect(text.contains("SIL OPEN FONT LICENSE Version 1.1"))
  }

  @Test("snapTheme 아래에서도 Font.snap 이 나눔스퀘어라운드로 그려진다(루트 설정이 사용자 지정 글꼴을 덮지 않는다)")
  func themeKeepsCustomFont() {
    let text = "정리 도우미 · 남은 기프티콘"
    for weight in SnapFont.Weight.allCases {
      let plain = self.png(Text(text).font(.snap(.headline, weight: weight)))
      let themed = self.png(VStack { Text(text).font(.snap(.headline, weight: weight)) }.snapTheme())
      let system = self.png(VStack { Text(text).font(.headline) }.snapTheme())
      #expect(themed == self.png(Text(text).font(.snap(.headline, weight: weight)).foregroundStyle(SnapColor.ink)))
      #expect(themed != system)
      #expect(plain != system)
    }
  }

  @Test("snapTheme 의 기본 본문 글꼴은 나눔스퀘어라운드 R 이다")
  func themeDefaultIsRegular() {
    let text = "사진 분류는 끝났습니다"
    let themed = self.png(VStack { Text(text) }.snapTheme())
    let expected = self.png(Text(text).font(.snap(.body)).foregroundStyle(SnapColor.ink))
    #expect(themed == expected)
  }

  private func png(_ view: some View) -> Data? {
    let renderer = ImageRenderer(content: view.frame(width: 320, height: 40).background(.white))
    renderer.scale = 2
    return renderer.uiImage?.pngData()
  }
}
