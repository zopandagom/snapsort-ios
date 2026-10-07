# 로컬·CI·Claude Code 가 모두 이 타깃을 쓴다. 명령을 바꿀 때는 여기만 고친다.
SHELL := /bin/bash
MISE := mise exec --

WORKSPACE := SnapSort.xcworkspace
SCHEME ?= SnapSort-Workspace
DESTINATION ?= platform=iOS Simulator,name=iPhone 17,OS=latest
RESULT_BUNDLE := build/TestResults.xcresult

.PHONY: bootstrap generate build test lint format clean

## 최초 1회: 도구 설치 + git 훅 연결
bootstrap:
	mise install
	git config core.hooksPath .githooks

generate:
	$(MISE) tuist generate --no-open

build: generate
	set -o pipefail && $(MISE) xcodebuild build \
		-workspace $(WORKSPACE) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO | $(MISE) xcbeautify

test: generate
	rm -rf $(RESULT_BUNDLE)
	set -o pipefail && $(MISE) xcodebuild test \
		-workspace $(WORKSPACE) -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-resultBundlePath $(RESULT_BUNDLE) \
		CODE_SIGNING_ALLOWED=NO | $(MISE) xcbeautify

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
