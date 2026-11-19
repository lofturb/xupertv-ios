import sys
import plistlib

path = sys.argv[1]
plist = {
    "CFBundleIdentifier": "org.videolan.ios.MobileVLCKit",
    "CFBundleName": "MobileVLCKit",
    "CFBundleExecutable": "MobileVLCKit",
    "CFBundlePackageType": "FMWK",
    "CFBundleShortVersionString": "3.3.1",
    "CFBundleVersion": "3.3.1",
    "MinimumOSVersion": "9.0",
}

with open(path, "wb") as handle:
    plistlib.dump(plist, handle)

print("ok")
