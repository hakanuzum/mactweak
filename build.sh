#!/bin/bash
# Builds MacTweak: build/MacTweak.app
#   ./build.sh            build
#   ./build.sh --install  build, copy to /Applications/MacTweak.app, restart the agent if it runs
set -euo pipefail
cd "$(dirname "$0")"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
TARGET=26.0
APP=build/MacTweak.app
C="$APP/Contents"
rm -rf build
mkdir -p "$C/MacOS" "$C/Frameworks" "$C/Resources" build/tmp

WARN="-Wall -Wextra -Wno-unused-parameter"

echo "› button themes (assets/button-themes)"
xcrun swiftc -O tools/pack_button_themes.swift -o build/tmp/pack-button-themes
build/tmp/pack-button-themes assets/button-themes build/tmp/button_themes.c build/tmp/ButtonThemes

echo "› core (libmactweak.dylib)"
# Deliberately links no frameworks: it is also injected into command line tools and does nothing there.
# arm64e: Apple's own apps; x86_64: apps running under Rosetta.
xcrun clang -fobjc-arc -Os $WARN -dynamiclib -arch arm64 -arch arm64e -arch x86_64 \
    -mmacosx-version-min=$TARGET -Wl,-dead_strip_dylibs -install_name @rpath/libmactweak.dylib \
    -Icore core/core.m core/corners.m core/titlebar.m core/buttons.m core/border.m build/tmp/button_themes.c \
    -o "$C/Frameworks/libmactweak.dylib" 2>&1 | grep -v 'arm64e.*ABI' || true
test -f "$C/Frameworks/libmactweak.dylib"
if otool -L "$C/Frameworks/libmactweak.dylib" | grep -q '\.framework/'; then
    echo "error: the core links a framework" >&2
    exit 1
fi

echo "› agent (mactweak-agent)"
xcrun clang -fobjc-arc -Os $WARN -arch arm64 -arch x86_64 -mmacosx-version-min=$TARGET \
    -framework Foundation agent/agent.m -o "$C/MacOS/mactweak-agent"

echo "› settings app (MacTweak)"
for arch in arm64 x86_64; do
    xcrun swiftc -O -swift-version 5 -target $arch-apple-macos$TARGET \
        -import-objc-header app/Bridge.h app/*.swift -o build/tmp/MacTweak-$arch
done
lipo -create build/tmp/MacTweak-arm64 build/tmp/MacTweak-x86_64 -output "$C/MacOS/MacTweak"

echo "› icon"
SET=build/tmp/AppIcon.iconset
mkdir -p "$SET"
if [[ -f icon/private/icon.png ]]; then
    # Local artwork (not in git): a 1024 px PNG, resized for every slot.
    for s in 16 32 128 256 512; do
        sips -z $s $s icon/private/icon.png --out "$SET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) icon/private/icon.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
    done
else
    xcrun swiftc -O icon/main.swift -o build/tmp/draw-icon
    build/tmp/draw-icon "$SET" assets/hand-high-contrast.svg
fi
iconutil -c icns "$SET" -o "$C/Resources/AppIcon.icns"

mkdir -p "$C/Resources/Icons"
cp assets/icons/*.svg "$C/Resources/Icons/"
cp -R build/tmp/ButtonThemes "$C/Resources/ButtonThemes"
cp app/Info.plist "$C/Info.plist"

echo "› ad-hoc signature"
codesign --force --sign - "$C/Frameworks/libmactweak.dylib"
codesign --force --sign - "$C/MacOS/mactweak-agent"
codesign --force --sign - "$APP"

echo "✓ $APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "› /Applications/MacTweak.app"
    rm -rf /Applications/MacTweak.app
    cp -R "$APP" /Applications/MacTweak.app
    LABEL=dev.hakanuzum.mactweak.agent
    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
        launchctl kickstart -k "gui/$(id -u)/$LABEL"
        echo "✓ agent restarted (core updated)"
    fi
fi
