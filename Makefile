THEOS ?= $(HOME)/theos
TARGET := iphone:clang:9.3:5.0
ARCHS := armv7 arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = AppleTVRemote

AppleTVRemote_FILES = \
    Classes/main.m \
    Classes/ATRAppDelegate.m \
    Classes/ATRRemoteViewController.m \
    Classes/ATRSettingsViewController.m \
    Classes/ATRAppsViewController.m \
    Classes/ATRClient.m \
    Classes/ATRIconProvider.m \
    Classes/ATRTrackpadView.m \
    Classes/ATRDeviceDiscovery.m \
    Classes/Crypto/tweetnacl.c \
    Classes/Crypto/atr_chacha20_poly1305.c \
    Classes/Companion/ATROpack.m \
    Classes/Companion/ATRCompanionClient.m

AppleTVRemote_FRAMEWORKS = UIKit CoreGraphics AudioToolbox QuartzCore Security CFNetwork MediaPlayer
AppleTVRemote_CFLAGS = -fobjc-arc -O2 -IClasses -IClasses/Crypto -IClasses/Companion -Wno-enum-conversion -Wno-deprecated-declarations -Wno-nonnull
AppleTVRemote_CODESIGN_FLAGS = -Sentitlements.xml

include $(THEOS_MAKE_PATH)/application.mk

after-all::
	@mkdir -p packages
	@$(THEOS)/toolchain/linux/iphone/bin/ldid -Sentitlements.xml $(THEOS_OBJ_DIR)/AppleTVRemote.app
	@rm -rf Payload
	@mkdir Payload
	@cp -r $(THEOS_OBJ_DIR)/AppleTVRemote.app Payload/
	@zip -qr packages/AppleTVRemote.ipa Payload
	@rm -rf Payload
	@echo "==> [SUCCESS] IPA created at packages/AppleTVRemote.ipa"
