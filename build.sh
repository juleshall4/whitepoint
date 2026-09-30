#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p 'White Point.app/Contents/MacOS'
mkdir -p .build
xcrun clang -target arm64-apple-macos13.0 -fobjc-arc -c Sources/NightShift.m -o .build/NightShift.o
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos13.0 -import-objc-header Sources/NightShift.h Sources/*.swift .build/NightShift.o -o 'White Point.app/Contents/MacOS/WhitePoint' -framework AppKit -framework CoreGraphics -framework Carbon -framework ServiceManagement -framework CoreLocation
cp Info.plist 'White Point.app/Contents/Info.plist'
codesign --force --sign - 'White Point.app'
