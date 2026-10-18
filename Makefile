# 로컬·CI·Claude Code 가 모두 이 타깃을 쓴다. 명령을 바꿀 때는 여기만 고친다.
SHELL := /bin/bash
MISE := mise exec --

WORKSPACE := SnapSort.xcworkspace
SCHEME ?= SnapSort-Workspace
DESTINATION ?= platform=iOS Simulator,name=iPhone 17,OS=latest
RESULT_BUNDLE := build/TestResults.xcresult

.PHONY: bootstrap generate project build test test-hooks test-scripts mask-samples lint format clean

## 최초 1회: 도구 설치 + git 훅 연결
bootstrap:
	mise install
	git config core.hooksPath .githooks

## 워크스페이스를 생성하고 Xcode 로 연다 (사람이 쓰는 타깃)
generate:
	$(MISE) tuist generate

## 생성만 하고 열지 않는다. build·test·CI 는 이 타깃을 거친다
project:
	$(MISE) tuist generate --no-open

build: project
	set -o pipefail && $(MISE) xcodebuild build \
		-workspace $(WORKSPACE) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO | $(MISE) xcbeautify

test: project
	rm -rf $(RESULT_BUNDLE)
	$(MAKE) --no-print-directory test-hooks
	set -o pipefail && $(MISE) xcodebuild test \
		-workspace $(WORKSPACE) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-resultBundlePath $(RESULT_BUNDLE) \
		CODE_SIGNING_ALLOWED=NO | $(MISE) xcbeautify

## git 훅 동작 테스트: 임시 레포에서 main 커밋·머지 커밋·push 차단과 기능 브랜치 통과 확인 (make test 가 포함)
test-hooks:
	./.githooks/test-hooks.sh

## scripts/ 의 개발 스크립트 테스트 (scripts/·Makefile 이나 스크립트가 읽는 파일이 바뀌면 /pr 이 실행. make test·CI 에는 들지 않는다)
## 시스템 python3(3.9)는 찾은 테스트가 0개여도 성공으로 끝나므로, 0개면 실패로 본다.
test-scripts:
	@out=$$(python3 -I -m unittest discover -s scripts -p 'test_*.py' 2>&1); status=$$?; echo "$$out"; \
	if grep -q '^Ran 0 tests' <<<"$$out"; then echo "FAIL 스크립트 테스트를 찾지 못했습니다 (scripts/test_*.py)" >&2; exit 1; fi; \
	exit $$status

## 기록 도구 샘플 초안의 OCR 줄을 가린다: make mask-samples FILE=<초안.json> (docs/CONVENTIONS.md §3)
mask-samples:
	$(if $(FILE),,$(error FILE=<초안.json> 이 필요합니다))
	python3 -I scripts/mask-samples.py "$(FILE)"

lint:
	$(MISE) swiftformat --lint .
	$(MISE) swiftlint lint --strict --quiet

format:
	$(MISE) swiftformat .
	$(MISE) swiftlint lint --fix --quiet

clean:
	$(MISE) tuist clean
	rm -rf build *.xcworkspace
	find . -path ./.git -prune -o \( -name '*.xcodeproj' -o -name Derived \) -prune -exec rm -rf {} +
