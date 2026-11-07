ARCHS = armv7 arm64
TARGET := iphone:7.1:5.0

INSTALL_TARGET_PROCESSES = Pinterest

# Force Xcode 26: the Xcode 27 linker drops the Thumb bit from armv7 __mod_init_func
# pointers, so the dylib crashes in dyld on iOS 6.
XCODE26_APP ?= /Applications/Xcode 26.6.app
XCODE26_LINK := $(CURDIR)/.theos/Xcode26.app
$(shell mkdir -p "$(CURDIR)/.theos" && ln -sfn "$(XCODE26_APP)" "$(XCODE26_LINK)")
export DEVELOPER_DIR := $(XCODE26_LINK)/Contents/Developer
MAKE := $(DEVELOPER_DIR)/usr/bin/make
_PF_TC := $(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/bin
TARGET_CC := $(_PF_TC)/clang
TARGET_CXX := $(_PF_TC)/clang++
TARGET_LD := $(_PF_TC)/clang
TARGET_LIPO := $(_PF_TC)/lipo
TARGET_STRIP := $(_PF_TC)/strip
TARGET_DSYMUTIL := $(_PF_TC)/dsymutil
TARGET_CODESIGN_ALLOCATE := $(_PF_TC)/codesign_allocate
export TARGET_CC TARGET_CXX TARGET_LD TARGET_LIPO TARGET_STRIP TARGET_DSYMUTIL TARGET_CODESIGN_ALLOCATE

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PinterestFix

PinterestFix_FILES = Tweak.x
PinterestFix_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

# ------------------------------- PACKAGE PIPELINES -------------------------------
# Do NOT indent the ifeq/else/endif — they must be at top level.
# Force sequential execution to avoid grouped/buffered output on older make.
.NOTPARALLEL: after-stage after-package dev-pipeline release-pipeline
MAKEFLAGS += -j1

ifeq ($(FINALPACKAGE),)
after-package:: dev-pipeline
else
after-package:: release-pipeline
endif

.PHONY: dev-pipeline release-pipeline

dev-pipeline:
	# Mirror progress to stderr (unbuffered) so you see something even if stdout is grouped.
	@echo "[📌] Starting Build on DEV Pipeline" 1>&2
	# Run everything under a PTY so child tools line-buffer their output.
	@script -q /dev/null /bin/bash -lc 'set -euo pipefail; \
		echo "[ℹ️ ] Locating latest .deb…"; \
		DEB="$$(ls -t "$(THEOS_PACKAGE_DIR)"/*.deb | head -1)"; \
		if [ -z "$$DEB" ] || [ ! -f "$$DEB" ]; then echo "[❌] No .deb found in $(THEOS_PACKAGE_DIR)"; exit 1; fi; \
		echo "[ℹ️ ] Found: $$DEB"; \
		BASE="$$(basename "$$DEB" .deb)"; TMP="$${BASE#*_}"; VERSION="$${TMP%_*}"; \
		echo "[ℹ️ ] Version: $$VERSION"; \
		echo "[📦] Git commit…"; \
		git add -u; \
		if git commit -m "Build $$VERSION"; then echo "[✅] Commit successful"; else echo "[⚠️ ] Nothing to commit"; fi; \
		DEST="/Volumes/victor/Sites/repo-dev/debs"; \
		echo "[📂] Copy .deb → $$DEST"; \
		mkdir -p "$$DEST"; cp -v "$$DEB" "$$DEST/"; \
		echo "[⚙️ ] Run repo update…"; \
		cd /Volumes/victor/Sites/repo-dev; \
		if [ -x ./Update.sh ]; then ./Update.sh; \
		elif [ -x ./update.sh ]; then ./update.sh; \
		elif [ -f ./Update.sh ]; then /bin/bash ./Update.sh; \
		elif [ -f ./update.sh ]; then /bin/bash ./update.sh; \
		else echo "[⚠️ ] Warning: update script not found"; fi; \
		echo "[✅] Repo update finished"; \
		MSG="Built $$VERSION and updated repo"; \
		echo "[🔔] Notifying macOS…"; \
		/usr/bin/osascript -e "display notification \"$$MSG\" with title \"PinterestFix Build\" subtitle \"Deployment complete\"" \
		&& echo "[✅] Notification sent" || echo "[⚠️ ] Could not display notification"'

release-pipeline:
	@echo "[📌] Starting Build on RELEASE Pipeline" 1>&2
	@script -q /dev/null /bin/bash -lc 'set -euo pipefail; \
	DEB="$$(ls -t "$(THEOS_PACKAGE_DIR)"/*.deb | head -1)"; \
	if [ -z "$$DEB" ] || [ ! -f "$$DEB" ]; then echo "[❌] No .deb found in $(THEOS_PACKAGE_DIR)"; exit 1; fi; \
	BASE="$$(basename "$$DEB" .deb)"; TMP="$${BASE#*_}"; VER="$${TMP%_*}"; \
	echo "[🚀 RELEASE] Built $$DEB (Version: $$VER)"; \
	echo "[ℹ️ ] (Release mode: no deploy; just committing)"; \
	git add -u || true; \
	if git commit -m "Release $$VER"; then \
		echo "[✅] Git commit: Release $$VER"; \
	else \
		echo "[⚠️ ] Nothing to commit"; \
	fi;'
SUBPROJECTS += PinterestFixPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
