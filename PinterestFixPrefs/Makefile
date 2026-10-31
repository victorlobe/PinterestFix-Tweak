ARCHS = armv7 arm64
TARGET := iphone:7.1

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = PinterestFixPrefs

PinterestFixPrefs_FILES = PFXRootListController.m
PinterestFixPrefs_FRAMEWORKS = UIKit
PinterestFixPrefs_PRIVATE_FRAMEWORKS = Preferences
PinterestFixPrefs_INSTALL_PATH = /Library/PreferenceBundles
PinterestFixPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
