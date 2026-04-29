# Chop — top-level developer commands.
# All targets wrap xcodegen + xcodebuild + swift-format. Xcode IDE is never required.

PROJECT      := Chop.xcodeproj
SCHEME       := Chop
CONFIG       := Debug
DERIVED      := build
APP_PATH     := $(DERIVED)/Build/Products/$(CONFIG)/Chop.app
APP_RELEASE  := $(DERIVED)/Build/Products/Release/Chop.app
INSTALL_PATH := /Applications/Chop.app

XCODEBUILD  := xcodebuild
XCODEGEN    := xcodegen
SWIFT_FORMAT := $(shell xcrun -f swift-format 2>/dev/null)
SOURCE_DIRS := Chop ChopCLI ChopTests

XCODEBUILD_FLAGS := \
  -project $(PROJECT) \
  -scheme $(SCHEME) \
  -configuration $(CONFIG) \
  -derivedDataPath $(DERIVED) \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

XCODEBUILD_RELEASE_FLAGS := \
  -project $(PROJECT) \
  -scheme $(SCHEME) \
  -configuration Release \
  -derivedDataPath $(DERIVED) \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# Tests build for a single (active) arch — the @testable swiftmodule is
# emitted per-arch, so tests must compile against the same arch as the host.
HOST_ARCH := $(shell uname -m)
XCODEBUILD_TEST_FLAGS := \
  -project $(PROJECT) \
  -scheme $(SCHEME) \
  -configuration $(CONFIG) \
  -derivedDataPath $(DERIVED) \
  -destination "platform=macOS,arch=$(HOST_ARCH)" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

.PHONY: help generate build run log test lint format check clean icon install

help:
	@printf "Chop — Make targets\n"
	@printf "  make generate   xcodegen → %s\n" "$(PROJECT)"
	@printf "  make build      build the app (auto-regenerates project)\n"
	@printf "  make run        build + open Chop.app (no console output)\n"
	@printf "  make log        build + run the app attached to this terminal\n"
	@printf "                  (chopLog() writes to stderr; nothing hits the\n"
	@printf "                  system log)\n"
	@printf "  make test       run the Swift Testing suite\n"
	@printf "  make lint       swift-format lint --strict\n"
	@printf "  make format     swift-format format --in-place\n"
	@printf "  make check      lint + test (pre-commit gate)\n"
	@printf "  make icon       sips/iconutil → Resources/Chop.icns from Chop-master.png\n"
	@printf "  make install    Release build → quit running Chop → replace %s\n" "$(INSTALL_PATH)"
	@printf "  make clean      remove build/ and the generated %s\n" "$(PROJECT)"

# Auto-regenerate the .xcodeproj when project.yml changes.
$(PROJECT): project.yml
	$(XCODEGEN) generate --spec project.yml

generate: $(PROJECT)

build: $(PROJECT)
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) build | tee $(DERIVED)/last-build.log | xcbeautify 2>/dev/null || true; \
	test "$${PIPESTATUS[0]:-0}" = "0"

run: build
	@if [ -d "$(APP_PATH)" ]; then \
	  open "$(APP_PATH)"; \
	else \
	  echo "Build artifact not found at $(APP_PATH)"; exit 1; \
	fi

# Run the app's binary directly so stdio is attached to this terminal —
# chopLog() will then stream to stderr. The app's runloop blocks until
# Chop quits (Cmd+Q) or you Ctrl+C the process.
log: build
	@if [ ! -d "$(APP_PATH)" ]; then \
	  echo "Build artifact not found at $(APP_PATH)"; exit 1; \
	fi
	@printf "Running %s in foreground (Cmd+Q to quit, Ctrl+C to terminate)\n" "$(APP_PATH)"
	@"$(APP_PATH)/Contents/MacOS/Chop"

test: $(PROJECT)
	$(XCODEBUILD) $(XCODEBUILD_TEST_FLAGS) test

lint:
	@if [ -z "$(SWIFT_FORMAT)" ]; then \
	  echo "swift-format not found via 'xcrun -f swift-format'"; exit 1; \
	fi
	@$(SWIFT_FORMAT) lint --strict --recursive $(SOURCE_DIRS)

format:
	@if [ -z "$(SWIFT_FORMAT)" ]; then \
	  echo "swift-format not found via 'xcrun -f swift-format'"; exit 1; \
	fi
	@$(SWIFT_FORMAT) format --in-place --recursive $(SOURCE_DIRS)

check: lint test

icon: Chop-master.png
	@rm -rf Chop.iconset Resources/Chop.icns
	@mkdir -p Chop.iconset Resources
	sips -z 16 16     Chop-master.png --out Chop.iconset/icon_16x16.png       > /dev/null
	sips -z 32 32     Chop-master.png --out Chop.iconset/icon_16x16@2x.png    > /dev/null
	sips -z 32 32     Chop-master.png --out Chop.iconset/icon_32x32.png       > /dev/null
	sips -z 64 64     Chop-master.png --out Chop.iconset/icon_32x32@2x.png    > /dev/null
	sips -z 128 128   Chop-master.png --out Chop.iconset/icon_128x128.png     > /dev/null
	sips -z 256 256   Chop-master.png --out Chop.iconset/icon_128x128@2x.png  > /dev/null
	sips -z 256 256   Chop-master.png --out Chop.iconset/icon_256x256.png     > /dev/null
	sips -z 512 512   Chop-master.png --out Chop.iconset/icon_256x256@2x.png  > /dev/null
	sips -z 512 512   Chop-master.png --out Chop.iconset/icon_512x512.png     > /dev/null
	sips -z 1024 1024 Chop-master.png --out Chop.iconset/icon_512x512@2x.png  > /dev/null
	iconutil -c icns Chop.iconset -o Resources/Chop.icns
	@rm -rf Chop.iconset

install: $(PROJECT)
	@printf "Building Release configuration...\n"
	$(XCODEBUILD) $(XCODEBUILD_RELEASE_FLAGS) build | tee $(DERIVED)/last-install-build.log | xcbeautify 2>/dev/null || true; \
	test "$${PIPESTATUS[0]:-0}" = "0"
	@if [ ! -d "$(APP_RELEASE)" ]; then \
	  echo "Release build artifact not found at $(APP_RELEASE)"; exit 1; \
	fi
	@printf "Asking any running Chop to quit...\n"
	@osascript -e 'tell application "Chop" to quit' 2>/dev/null || true
	@# Wait briefly for the graceful quit, then SIGTERM anything still alive.
	@for i in 1 2 3 4 5 6 7 8; do pgrep -x Chop >/dev/null || break; sleep 0.25; done
	@pkill -x Chop 2>/dev/null || true
	@if [ -d "$(INSTALL_PATH)" ]; then \
	  printf "Removing existing %s\n" "$(INSTALL_PATH)"; \
	  rm -rf "$(INSTALL_PATH)"; \
	fi
	@printf "Installing %s → %s\n" "$(APP_RELEASE)" "$(INSTALL_PATH)"
	@cp -R "$(APP_RELEASE)" "$(INSTALL_PATH)"
	@printf "Installed. Launch with: open %s\n" "$(INSTALL_PATH)"

clean:
	rm -rf $(DERIVED) $(PROJECT)
