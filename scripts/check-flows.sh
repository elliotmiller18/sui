#!/bin/sh
# Compatibility entry point; all checks now run without leaving build artifacts.
set -eu
exec "$(dirname "$0")/test.sh" "$@"
