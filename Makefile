APP_NAME    := ClaudeQuota
VERSION     := 1.0.0
BUNDLE_ID   := com.claude.quota
DIST        := dist
APP_BUNDLE  := $(DIST)/$(APP_NAME).app
DMG_NAME    := $(APP_NAME)-$(VERSION)
BINARY      := .build/release/$(APP_NAME)
INSTALL_DIR := /Applications
AGENT_PLIST := $(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist
SIGN_ID     := $(shell security find-identity -v -p codesigning 2>/dev/null | grep "ClaudeQuota Dev" | head -1 | sed 's/.*"\(.*\)"/\1/' || echo "-")

.PHONY: all build bundle dmg install uninstall clean

all: dmg

# ── Build ────────────────────────────────────────────────────────

build:
	swift build -c release

# ── App Bundle ───────────────────────────────────────────────────

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(BINARY) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	chmod +x $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp packaging/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp packaging/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	printf 'APPL????' > $(APP_BUNDLE)/Contents/PkgInfo
	codesign --sign "$(SIGN_ID)" --force --deep --options runtime $(APP_BUNDLE)
	@echo "✓ $(APP_BUNDLE) created"

# ── DMG ──────────────────────────────────────────────────────────

dmg: bundle
	rm -rf $(DIST)/staging $(DIST)/$(DMG_NAME).dmg
	mkdir -p $(DIST)/staging
	cp -r $(APP_BUNDLE) $(DIST)/staging/
	ln -sf /Applications $(DIST)/staging/Applications
	hdiutil create \
		-volname "$(DMG_NAME)" \
		-srcfolder $(DIST)/staging \
		-ov -format UDZO \
		-imagekey zlib-level=9 \
		$(DIST)/$(DMG_NAME).dmg
	rm -rf $(DIST)/staging
	@echo "✓ $(DIST)/$(DMG_NAME).dmg created"

# ── Install ──────────────────────────────────────────────────────

install: bundle
	@# Stop existing instance
	-pkill -f "$(APP_NAME)" 2>/dev/null; sleep 1
	-launchctl unload $(AGENT_PLIST) 2>/dev/null
	@# Copy app
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -r $(APP_BUNDLE) $(INSTALL_DIR)/$(APP_NAME).app
	@# Create LaunchAgent
	@mkdir -p $(HOME)/Library/LaunchAgents
	/usr/libexec/PlistBuddy -c "Clear dict" /dev/null 2>/dev/null; \
	defaults write $(AGENT_PLIST) Label -string "$(BUNDLE_ID)"; \
	defaults write $(AGENT_PLIST) ProgramArguments -array "$(INSTALL_DIR)/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)"; \
	defaults write $(AGENT_PLIST) RunAtLoad -bool true; \
	defaults write $(AGENT_PLIST) KeepAlive -bool true; \
	defaults write $(AGENT_PLIST) StandardErrorPath -string "/tmp/claude-quota.log"; \
	plutil -convert xml1 $(AGENT_PLIST)
	launchctl load $(AGENT_PLIST)
	@echo "✓ Installed to $(INSTALL_DIR) and LaunchAgent loaded"

# ── Uninstall ────────────────────────────────────────────────────

uninstall:
	-pkill -f "$(APP_NAME)" 2>/dev/null
	-launchctl unload $(AGENT_PLIST) 2>/dev/null
	rm -f $(AGENT_PLIST)
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	@echo "✓ Uninstalled"

# ── Clean ────────────────────────────────────────────────────────

clean:
	rm -rf $(DIST) .build
