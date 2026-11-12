#!/bin/sh
# Build and test an isolated copy; always remove binaries, logs and solve outputs.
set -eu
cd "$(dirname "$0")/.."
case "${1:-}" in
    ""|--preflop|--sizes|--flop|--handoff) ;;
    *) echo "Usage: $0 [--preflop|--sizes|--flop|--handoff]" >&2; exit 2 ;;
esac
WORKSPACE=$(mktemp -d "${TMPDIR:-/tmp}/sui-tests.XXXXXX")
cleanup() { rm -rf "$WORKSPACE"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export COPYFILE_DISABLE=1 PYTHONDONTWRITEBYTECODE=1
for path in Sources assets vendor scripts tests docs README.md THIRD_PARTY_NOTICES.md LICENSE; do
    if [ -e "$path" ]; then cp -R "$path" "$WORKSPACE/"; fi
done
mkdir "$WORKSPACE/tmp"
export TMPDIR="$WORKSPACE/tmp/"
export CLANG_MODULE_CACHE_PATH="$TMPDIR/clang-module-cache"
cd "$WORKSPACE"
./scripts/build.sh
python3 tests/smoke.py
python3 tests/packaging.py
python3 tests/solver-optimizations.py
python3 tests/solver-preview.py
SDK=$(xcrun --show-sdk-path)
set -- "${1:-}"
CHECK_MODE=$1
set --
if swiftc --version | /usr/bin/grep -q 'Swift version 5.10' && [ -f build/toolchain-overlay.json ]; then
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk
    set -- -vfsoverlay "$PWD/build/toolchain-overlay.json" -Xcc -ivfsoverlay -Xcc "$PWD/build/toolchain-overlay.json"
fi
swiftc -sdk "$SDK" "$@" -module-cache-path "$TMPDIR/swift-module-cache" Sources/Core.swift Sources/Preflop.swift Sources/Postflop.swift Sources/Solver.swift tests/solver-budget.swift -o build/solver-budget
./build/solver-budget
swiftc -sdk "$SDK" "$@" -module-cache-path "$TMPDIR/swift-module-cache" Sources/Core.swift Sources/Preflop.swift Sources/Postflop.swift Sources/Solver.swift tests/suit-combos.swift -o build/suit-combos
./build/suit-combos
swiftc -sdk "$SDK" "$@" -module-cache-path "$TMPDIR/swift-module-cache" Sources/Core.swift Sources/Preflop.swift Sources/Postflop.swift Sources/Solver.swift tests/flow-smoke.swift -o build/flow-smoke
if [ -n "$CHECK_MODE" ]; then
    ./build/flow-smoke "$CHECK_MODE"
else
    ./build/flow-smoke --sizes
    ./build/flow-smoke --flop --handoff
fi
printf 'Regression checks passed; temporary workspace will be removed.\n'
