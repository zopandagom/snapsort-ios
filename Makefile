# 로컬·CI·Claude Code 가 모두 이 타깃을 쓴다. 명령을 바꿀 때는 여기만 고친다.
SHELL := /bin/bash
MISE := mise exec --

WORKSPACE := SnapSort.xcworkspace
SCHEME ?= SnapSort-Workspace
DESTINATION ?= platform=iOS Simulator,name=iPhone 17,OS=latest
RESULT_BUNDLE := build/TestResults.xcresult

.PHONY: bootstrap generate project build test test-hooks lint format clean

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

## git 훅 동작 테스트: 임시 레포에서 main 커밋·push 차단과 기능 브랜치 통과 확인 (make test 가 포함)
test-hooks:
	./.githooks/test-hooks.sh

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
