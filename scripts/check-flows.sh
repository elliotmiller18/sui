#!/bin/sh
# Small integration check; runs the installed solver on narrow ranges.
set -eu
cd "$(dirname "$0")/.."
./scripts/build.sh
SDK="$(xcrun --show-sdk-path)"
CHECK_FLOP="${1:-}"
set --
if swiftc --version | /usr/bin/grep -q 'Swift version 5.10' && [ -f build/toolchain-overlay.json ]; then
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk
    set -- -vfsoverlay "$PWD/build/toolchain-overlay.json" -Xcc -ivfsoverlay -Xcc "$PWD/build/toolchain-overlay.json"
fi
swiftc -sdk "$SDK" "$@" -module-cache-path "${TMPDIR:-/tmp}/sui-swift-fixed" Sources/Core.swift Sources/Preflop.swift Sources/Postflop.swift Sources/Solver.swift scripts/flow-smoke.swift -o build/flow-smoke
./build/flow-smoke "$CHECK_FLOP"
