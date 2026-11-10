DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

SCHEME := FairMile
DESTINATION ?= platform=iOS Simulator,name=iPhone 17,OS=latest

.PHONY: generate build test

generate:
	xcodegen generate

build: generate
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' build

test: generate
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' test
