#!/bin/zsh
# Builds a universal (Apple silicon + Intel), ad-hoc signed syncR.app and zips it into build/.
set -e
cd "${0:A:h}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP=build/syncR.app
rm -rf build && mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $arch-apple-macos15.0 Sources/*.swift -o build/syncR-$arch
done
lipo -create build/syncR-arm64 build/syncR-x86_64 -output "$APP/Contents/MacOS/syncR"
rm build/syncR-arm64 build/syncR-x86_64
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force -s - "$APP"
ditto -c -k --keepParent "$APP" "build/syncR-$VERSION.zip"
echo "built: build/syncR-$VERSION.zip"
