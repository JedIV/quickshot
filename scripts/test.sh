#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
"$ROOT/build.sh"
export QUICKSHOT_TEST_OUTPUT="$ROOT/build/test-results"
"$ROOT/build/Quickshot.app/Contents/MacOS/Quickshot" --self-test
