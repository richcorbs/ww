#!/usr/bin/env bash
# Test runner for wt

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Running wt test suite..."
echo ""

"${SCRIPT_DIR}/tests/test-all.sh"

exit $?
