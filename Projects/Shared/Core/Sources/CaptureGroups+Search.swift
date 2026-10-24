/// 묶음 값 별칭 하나: 정규화한 UTF-8 바이트와 결과 줄에 보일 표의 이름 (docs/ARCHITECTURE.md §4 검색).
struct SearchTerm: Sendable, Hashable {
  let bytes: [UInt8]
  let title: String

  init(normalized: String, title: String) {
    self.bytes = Array(normalized.utf8)
    self.title = title
  }
}

extension CaptureGroups {
  /// 별칭 목록을 나누는 키: 식별자 묶음. 몰·브랜드는 표에서만 만들어져 식별자가 같으면 별칭도 같다
  /// (나중에 public init 이 생기면 이 가정이 깨진다). 합성 Hashable 은 표의 낱말·줄까지 해시해 느려 쓰지 않는다.
  var searchKey: String {
    let regionIDs = self.regions.map(\.id).sorted().joined(separator: ",")
    return "\(self.mall?.id ?? "")|\(self.brand?.id ?? "")|\(self.chatApp?.rawValue ?? "")|\(regionIDs)"
  }

  /// 검색이 대조하는 별칭. 몰·브랜드는 이름·낱말·줄 별칭, 대화 앱은 이름, 지역은 시·도의 모든 별칭과 시·군·구 이름.
  /// 도메인·대화 앱 UI 문구는 넣지 않는다(문구는 OCR 줄로 나온다).
  var searchTerms: [SearchTerm] {
    var terms: [SearchTerm] = []
    if let mall = self.mall {
      terms += ([mall.name] + mall.words + mall.lines)
        .map { SearchTerm(normalized: SearchText.normalize($0), title: mall.name) }
    }
    if let brand = self.brand {
      terms += ([brand.name] + brand.words + brand.lines)
        .map { SearchTerm(normalized: SearchText.normalize($0), title: brand.name) }
    }
    if let chatApp = self.chatApp {
      terms.append(SearchTerm(normalized: SearchText.normalize(chatApp.name), title: chatApp.name))
    }
    for region in self.regions.sorted() {
      var names = KoreanAdministrativeDivisions.aliases(of: region.province)
      if let district = region.district {
        names.append(district)
      }
      terms += names.map { SearchTerm(normalized: SearchText.normalize($0), title: region.title) }
    }
    return terms
  }
}
