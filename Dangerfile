# SwiftLint 위반을 PR 의 해당 줄에 코멘트로 단다.
# CI lint 잡이 Docker 로 SwiftLint 를 돌려 build/swiftlint.json 을 남긴 뒤 이 파일을 실행한다.
# --strict 와 같게 모든 위반을 실패로 처리한다. diff 밖 줄의 위반은 Danger 요약 코멘트에 모인다.
require "json"

report = "build/swiftlint.json"

begin
  violations = JSON.parse(File.read(report))
rescue Errno::ENOENT, JSON::ParserError => e
  fail("SwiftLint 결과를 읽지 못했습니다 (`#{report}`): #{e.message}")
  violations = []
end

violations.each do |v|
  # Docker 컨테이너 안의 절대 경로(/work/...)를 레포 상대 경로로 바꾼다.
  file = v["file"].to_s.delete_prefix("/work/")
  fail("**SwiftLint** `#{v["rule_id"]}`: #{v["reason"]}", file: file, line: v["line"])
end
