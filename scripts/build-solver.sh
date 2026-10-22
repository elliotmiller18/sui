#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# OpenMP is the solver's sole non-system runtime library. Bundle it with the CLI.
LLVM_ROOT="${SUI_LLVM_ROOT:-/opt/homebrew/opt/llvm}"
OMP_HEADER=$(find "$LLVM_ROOT/lib/clang" -name omp.h -print | head -1)
mkdir -p build/omp-include
if ! cmp -s "$OMP_HEADER" build/omp-include/omp.h; then
    cp -f "$OMP_HEADER" build/omp-include/omp.h
fi
SDK=$(xcrun --show-sdk-path)
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk ]; then
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk
fi
cmake -S scripts/solver -B build/solver -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DCMAKE_OSX_SYSROOT="$SDK" \
    -DOMP_INCLUDE="$PWD/build/omp-include" -DOMP_LIBRARY="$LLVM_ROOT/lib/libomp.dylib"
cmake --build build/solver -j 4
DEST=build/Sui.app/Contents/Resources/solver
mkdir -p "$DEST"
cp build/solver/console_solver "$DEST/console_solver"
cp -f "$LLVM_ROOT/lib/libomp.dylib" "$DEST/libomp.dylib"
install_name_tool -change "$LLVM_ROOT/lib/libomp.dylib" '@executable_path/libomp.dylib' "$DEST/console_solver"
chmod u+w "$DEST/libomp.dylib"
install_name_tool -id '@executable_path/libomp.dylib' "$DEST/libomp.dylib"
codesign --force --sign - "$DEST/libomp.dylib"
codesign --force --sign - "$DEST/console_solver"
cp -R assets/solver/. "$DEST/"
cp "$LLVM_ROOT/LICENSE.TXT" "$DEST/OpenMP-LICENSE.txt"
cp vendor/TexasSolver-console/LICENSE "$DEST/TexasSolver-LICENSE"
cp vendor/TexasSolver-console/ext/fmt/LICENSE.rst "$DEST/fmt-LICENSE"
# Include corresponding fork sources and the build recipe with the local app.
tar -czf "$DEST/solver-source.tar.gz" scripts/solver scripts/build-solver.sh \
    vendor/TexasSolver-console/src vendor/TexasSolver-console/include \
    vendor/TexasSolver-console/ext/fmt vendor/TexasSolver-console/LICENSE \
    vendor/TexasSolver-console/SUI-FORK.md
