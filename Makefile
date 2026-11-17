THEOS ?= $(HOME)/theos
TARGET := iphone:clang:6.1:5.0
ARCHS := armv7

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
    Classes/Crypto/tweetnacl.c \
    Classes/Crypto/atr_chacha20_poly1305.c \
    Classes/Companion/ATROpack.m \
    Classes/Companion/ATRCompanionClient.m

AppleTVRemote_FRAMEWORKS = UIKit CoreGraphics AudioToolbox QuartzCore Security CFNetwork
AppleTVRemote_CFLAGS = -fobjc-arc -O2 -IClasses -IClasses/Crypto -IClasses/Companion

include $(THEOS_MAKE_PATH)/application.mk

after-all::
	@mkdir -p packages
	@rm -rf Payload
	@mkdir Payload
	@cp -r $(THEOS_OBJ_DIR)/AppleTVRemote.app Payload/
	@zip -qr packages/AppleTVRemote.ipa Payload
	@rm -rf Payload
	@echo "==> [SUCCESS] IPA created at packages/AppleTVRemote.ipa"
