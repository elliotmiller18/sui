#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/Sui.app/Contents/MacOS
./scripts/build-solver.sh
# Use the SDK matching Apple's Swift 5.10 when that older toolchain is installed.
SDK="$(xcrun --show-sdk-path)"
if swiftc --version | /usr/bin/grep -q 'Swift version 5.10' && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk ]; then
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk
fi
# Some mixed CLT installations declare SwiftBridging twice. Hide the duplicate
# through a compiler overlay; do not edit the system toolchain.
set --
if swiftc --version | /usr/bin/grep -q 'Swift version 5.10' && [ -f /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap ]; then
    printf '' > build/empty.modulemap
    cat > build/toolchain-overlay.json <<OVERLAY
{"version":0,"roots":[{"type":"file","name":"/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap","external-contents":"$PWD/build/empty.modulemap"}]}
OVERLAY
    set -- -vfsoverlay "$PWD/build/toolchain-overlay.json" -Xcc -ivfsoverlay -Xcc "$PWD/build/toolchain-overlay.json"
fi
swiftc -O -sdk "$SDK" "$@" -module-cache-path "${TMPDIR:-/tmp}/sui-swift-fixed" Sources/*.swift -o build/Sui.app/Contents/MacOS/sui
ln -sf Sui.app/Contents/MacOS/sui build/sui
cat > build/Sui.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>sui</string>
<key>CFBundleIdentifier</key><string>local.sui.ranges</string>
<key>CFBundleName</key><string>Sui</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
# The bundled OpenMP runtime may require a newer macOS than the Swift UI.
RUNTIME_MIN=$(otool -l build/Sui.app/Contents/Resources/solver/libomp.dylib | awk '/minos/ {print $2; exit}')
if [ -n "$RUNTIME_MIN" ]; then
    /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $RUNTIME_MIN" build/Sui.app/Contents/Info.plist
fi
printf 'Built build/Sui.app and build/sui\n' 
