APP_NAME   := Doorman
VERSION    ?= $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
ifeq ($(VERSION),)
VERSION    := 0.0.0
endif
PREFIX     ?= /usr/local
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
# Homebrew passes --disable-sandbox: its own sandbox forbids SwiftPM's.
SWIFT_BUILD_FLAGS ?=

.PHONY: all app test install run clean

all: app

test:
	swift test $(SWIFT_BUILD_FLAGS)

app:
	swift build -c release $(SWIFT_BUILD_FLAGS)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build -c release $(SWIFT_BUILD_FLAGS) --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(APP)/Contents/Info.plist"
	plutil -replace CFBundleVersion -string "$(VERSION)" "$(APP)/Contents/Info.plist"
	codesign --force --sign - "$(APP)"

install: app
	mkdir -p "$(PREFIX)/bin"
	rm -rf "$(PREFIX)/$(APP_NAME).app"
	cp -R "$(APP)" "$(PREFIX)/$(APP_NAME).app"
	printf '#!/bin/sh\nexec open "%s" "$$@"\n' "$(PREFIX)/$(APP_NAME).app" > "$(PREFIX)/bin/doorman"
	chmod +x "$(PREFIX)/bin/doorman"

run: app
	open "$(APP)"

clean:
	rm -rf "$(BUILD_DIR)" .build
