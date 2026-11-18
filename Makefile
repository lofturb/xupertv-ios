TARGET = iphone:clang:9.3:9.0
ARCHS = armv7
INSTALL_PATH = /Applications

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = XuperTV

GCD_SRC = $(wildcard vendor/GCDWebServer/GCDWebServer/Core/*.m) \
          $(wildcard vendor/GCDWebServer/GCDWebServer/Requests/*.m) \
          $(wildcard vendor/GCDWebServer/GCDWebServer/Responses/*.m)

XuperTV_FILES = main.m AppDelegate.m RootViewController.m LocalServer.m $(GCD_SRC)
XuperTV_FRAMEWORKS = UIKit Foundation WebKit JavaScriptCore AVFoundation Security CoreGraphics
XuperTV_LDFLAGS = -Wl,-segalign,4000 -lz
XuperTV_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-parameter \
                 -Wno-unused-variable -Wno-unused-function \
                 -Ivendor/GCDWebServer/GCDWebServer/Core \
                 -Ivendor/GCDWebServer/GCDWebServer/Requests \
                 -Ivendor/GCDWebServer/GCDWebServer/Responses
XuperTV_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "killall -9 XuperTV 2>/dev/null || true"