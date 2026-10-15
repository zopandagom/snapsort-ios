#if DEBUG
  import Testing
  @testable import SampleRecorderFeature

  /// 샘플 보기 번호 목록 해석.
  struct SampleLookupTests {
    @Test(
      "쉼표·공백·줄바꿈으로 나누고 빈 토큰은 버리며, 앞자리 0 은 무시한다",
      arguments: [
        ("246, 586\n688  12,", [246, 586, 688, 12]),
        (" 007 ", [7]),
        ("1,,2", [1, 2]),
      ]
    )
    func splitsNumbers(input: String, expected: [Int]) {
      #expect(SampleLookup.numbers(from: input) == .success(expected))
    }

    @Test("1 이상의 정수가 아닌 토큰이 있으면 입력 순서대로 모아 전체를 거절한다")
    func rejectsInvalidTokens() {
      #expect(
        SampleLookup.numbers(from: "1, abc, 2, 1.5, -3, +4, 0")
          == .failure(.invalidTokens(["abc", "1.5", "-3", "+4", "0"]))
      )
    }

    @Test("빈 입력이나 구분자만 있으면 번호가 없다", arguments: ["", " , \n"])
    func rejectsEmpty(input: String) {
      #expect(SampleLookup.numbers(from: input) == .failure(.noNumbers))
    }

    @Test("중복은 처음 나온 것만 남기고 입력 순서를 지킨다")
    func removesDuplicates() {
      #expect(SampleLookup.numbers(from: "5 3 5 3 1") == .success([5, 3, 1]))
    }

    @Test("중복을 없앤 뒤 100개까지 받는다")
    func limitsCount() {
      let hundred = (1 ... 100).map(String.init)

      #expect(SampleLookup.numbers(from: hundred.joined(separator: ",")) == .success(Array(1 ... 100)))
      #expect(SampleLookup
        .numbers(from: (1 ... 101).map(String.init).joined(separator: ",")) == .failure(.tooMany(count: 101)))
      #expect(SampleLookup
        .numbers(from: (hundred + hundred.prefix(20)).joined(separator: " ")) == .success(Array(1 ... 100)))
    }
  }
#endif
