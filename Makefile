TARGET = iphone:clang:9.3:9.0
ARCHS = armv7
INSTALL_PATH = /Applications

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = XuperTV

GCD_SRC = $(wildcard vendor/GCDWebServer/GCDWebServer/Core/*.m) \
          $(wildcard vendor/GCDWebServer/GCDWebServer/Requests/*.m) \
          $(wildcard vendor/GCDWebServer/GCDWebServer/Responses/*.m)

XuperTV_FILES = main.m AppDelegate.m RootViewController.m LocalServer.m ServiceBridge.m HLSProxy.m XuperPlayerViewController.m $(GCD_SRC)
XuperTV_FRAMEWORKS = UIKit Foundation WebKit JavaScriptCore AVFoundation Security CoreGraphics MobileCoreServices SystemConfiguration MobileVLCKit
XuperTV_LDFLAGS = -Wl,-segalign,4000 -Wl,-undefined,dynamic_lookup -lz \
                 -Fvendor/vlckit/MobileVLCKit-binary -framework MobileVLCKit -lc++ -lstdc++ -lbz2 -liconv
XuperTV_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-parameter \
                 -Wno-unused-variable -Wno-unused-function \
                 -Fvendor/vlckit/MobileVLCKit-binary \
                 -Ivendor/GCDWebServer/GCDWebServer/Core \
                 -Ivendor/GCDWebServer/GCDWebServer/Requests \
                 -Ivendor/GCDWebServer/GCDWebServer/Responses
XuperTV_CODESIGN_FLAGS = -Sentitlements.plist

VLC_FRAMEWORK = vendor/vlckit/MobileVLCKit-binary/MobileVLCKit.framework

include $(THEOS_MAKE_PATH)/application.mk

before-package::
	@set -e; APP="$(THEOS_STAGING_DIR)/Applications/XuperTV.app"; \
	FRAMEWORKS="$$APP/Frameworks"; \
	mkdir -p "$$FRAMEWORKS"; \
	rm -rf "$$FRAMEWORKS/MobileVLCKit.framework"; \
	cp -R "$(THEOS_PROJECT_DIR)/$(VLC_FRAMEWORK)" "$$FRAMEWORKS/"; \
	$(THEOS)/bin/ldid -S"$$FRAMEWORKS/MobileVLCKit.framework/MobileVLCKit" || true; \
	rm -rf "$$APP/web" "$$APP/posters"; \
	mkdir -p "$$APP/web" "$$APP/posters"; \
	cp web/index.html web/ui.css web/xuper.js "$$APP/web/"; \
	cp posters/*.jpg "$$APP/posters/"

after-install::
	install.exec "killall -9 XuperTV 2>/dev/null || true"

