#!/usr/bin/env bash
# Test runner for ww

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check dependencies
MISSING_DEPS=()
command -v git >/dev/null 2>&1 || MISSING_DEPS+=("git")
command -v jq >/dev/null 2>&1 || MISSING_DEPS+=("jq")

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
  echo "Error: Missing required dependencies: ${MISSING_DEPS[*]}"
  echo "Install with: brew install ${MISSING_DEPS[*]}"
  exit 1
fi

echo "Running ww test suite..."
echo ""

"${SCRIPT_DIR}/tests/test-all.sh"

# Cleanup test repos on exit
trap 'rm -rf "${SCRIPT_DIR}/test-repos" 2>/dev/null || true' EXIT

exit $?
