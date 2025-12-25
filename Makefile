# Orbit - Makefile for build and release automation
#
# Usage:
#   make build          - Debug build
#   make release        - Release build with signing
#   make run            - Build and run debug
#   make clean          - Clean build artifacts
#   make dmg            - Create distributable DMG
#   make notarize       - Notarize the app (requires credentials)
#   make tag VERSION=x.y.z - Tag and push a release

# Configuration
APP_NAME := Orbit
SCHEME := orbit
PROJECT := orbit.xcodeproj
BUNDLE_ID := com.orbit.app
TEAM_ID := DN4YAHWP2P

# Paths
BUILD_DIR := $(HOME)/Library/Developer/Xcode/DerivedData/orbit-*/Build/Products
DEBUG_APP := $(BUILD_DIR)/Debug/$(APP_NAME).app
RELEASE_APP := $(BUILD_DIR)/Release/$(APP_NAME).app
DIST_DIR := ./dist
DMG_NAME := $(APP_NAME).dmg

# Colors
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m # No Color

.PHONY: all generate build release run clean dmg notarize tag help verify-sign

# Default target
all: build

# Generate Xcode project from project.yml
generate:
	@echo "$(GREEN)Generating Xcode project...$(NC)"
	xcodegen generate

# Debug build
build: generate
	@echo "$(GREEN)Building debug...$(NC)"
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build
	@echo "$(GREEN)Build complete: $(DEBUG_APP)$(NC)"

# Release build with code signing
release: generate
	@echo "$(GREEN)Building release...$(NC)"
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release clean build
	@echo "$(GREEN)Release complete: $(RELEASE_APP)$(NC)"
	@$(MAKE) verify-sign

# Build and run
run: build
	@echo "$(GREEN)Launching app...$(NC)"
	@pkill -f "$(APP_NAME).app" 2>/dev/null || true
	@sleep 0.5
	@open $(DEBUG_APP)

# Clean build artifacts
clean:
	@echo "$(YELLOW)Cleaning...$(NC)"
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>/dev/null || true
	rm -rf $(DIST_DIR)
	@echo "$(GREEN)Clean complete$(NC)"

# Verify code signature
verify-sign:
	@echo "$(GREEN)Verifying code signature...$(NC)"
	@codesign -dv --verbose=4 $(RELEASE_APP) 2>&1 | grep -E "(Authority|TeamIdentifier|Signature)"
	@echo ""
	@codesign --verify --deep --strict $(RELEASE_APP) && echo "$(GREEN)✓ Signature valid$(NC)" || echo "$(YELLOW)⚠ Signature invalid$(NC)"

# Create DMG for distribution
dmg: release
	@echo "$(GREEN)Creating DMG...$(NC)"
	@mkdir -p $(DIST_DIR)
	@rm -f $(DIST_DIR)/$(DMG_NAME)
	@# Create temporary directory for DMG contents
	@mkdir -p $(DIST_DIR)/dmg-tmp
	@cp -R $(RELEASE_APP) $(DIST_DIR)/dmg-tmp/
	@ln -s /Applications $(DIST_DIR)/dmg-tmp/Applications
	@# Create DMG
	@hdiutil create -volname "$(APP_NAME)" -srcfolder $(DIST_DIR)/dmg-tmp -ov -format UDZO $(DIST_DIR)/$(DMG_NAME)
	@rm -rf $(DIST_DIR)/dmg-tmp
	@echo "$(GREEN)DMG created: $(DIST_DIR)/$(DMG_NAME)$(NC)"
	@ls -lh $(DIST_DIR)/$(DMG_NAME)

# Notarize the app (requires Apple credentials in keychain)
# First, store credentials: xcrun notarytool store-credentials "notary-profile" --apple-id "email" --team-id "TEAM_ID"
notarize: dmg
	@echo "$(GREEN)Notarizing...$(NC)"
	@echo "$(YELLOW)Note: Requires credentials stored as 'notary-profile'$(NC)"
	@echo "$(YELLOW)Run: xcrun notarytool store-credentials \"notary-profile\" --apple-id YOUR_APPLE_ID --team-id $(TEAM_ID)$(NC)"
	@xcrun notarytool submit $(DIST_DIR)/$(DMG_NAME) --keychain-profile "notary-profile" --wait
	@xcrun stapler staple $(DIST_DIR)/$(DMG_NAME)
	@echo "$(GREEN)Notarization complete$(NC)"

# Tag a release
# Usage: make tag VERSION=0.2.3
tag:
ifndef VERSION
	$(error VERSION is not set. Usage: make tag VERSION=x.y.z)
endif
	@echo "$(GREEN)Tagging v$(VERSION)...$(NC)"
	@git tag -a v$(VERSION) -m "Release v$(VERSION)"
	@git push origin v$(VERSION)
	@echo "$(GREEN)Tag v$(VERSION) pushed$(NC)"

# Full release process
# Usage: make full-release VERSION=0.2.3
full-release: release dmg
ifndef VERSION
	$(error VERSION is not set. Usage: make full-release VERSION=x.y.z)
endif
	@echo "$(GREEN)Creating full release v$(VERSION)...$(NC)"
	@cp -R $(RELEASE_APP) ~/Desktop/
	@cp $(DIST_DIR)/$(DMG_NAME) ~/Desktop/$(APP_NAME)-v$(VERSION).dmg
	@$(MAKE) tag VERSION=$(VERSION)
	@echo ""
	@echo "$(GREEN)═══════════════════════════════════════$(NC)"
	@echo "$(GREEN)Release v$(VERSION) complete!$(NC)"
	@echo "$(GREEN)═══════════════════════════════════════$(NC)"
	@echo "  App: ~/Desktop/$(APP_NAME).app"
	@echo "  DMG: ~/Desktop/$(APP_NAME)-v$(VERSION).dmg"
	@echo "  Tag: v$(VERSION)"
	@echo ""

# Help
help:
	@echo "Orbit Build System"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  build        - Debug build"
	@echo "  release      - Release build with code signing"
	@echo "  run          - Build and run debug"
	@echo "  clean        - Clean build artifacts"
	@echo "  dmg          - Create distributable DMG"
	@echo "  notarize     - Notarize the DMG (requires credentials)"
	@echo "  tag          - Tag a release (VERSION=x.y.z)"
	@echo "  full-release - Complete release (VERSION=x.y.z)"
	@echo "  verify-sign  - Verify code signature"
	@echo "  help         - Show this help"
	@echo ""
	@echo "Examples:"
	@echo "  make run"
	@echo "  make full-release VERSION=0.2.4"
	@echo "  make tag VERSION=0.3.0"
