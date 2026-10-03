#!/bin/zsh
# Builds syncR.app into ~/Applications (ad-hoc signed).
set -e
cd "${0:A:h}"
APP=${APP:-~/Applications/syncR.app}
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/syncR"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force -s - "$APP"
echo "built: $APP"
