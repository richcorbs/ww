#!/usr/bin/env bash
# Uninstall script for ww (worktree workflow manager)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/richcorbs/ww/main/uninstall.sh | bash
#
#   Or locally:
#   ./uninstall.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_LOCATION="$HOME/.local/share/ww"

error() {
  echo -e "${RED}Error: $1${NC}" >&2
  exit 1
}

warn() {
  echo -e "${YELLOW}Warning: $1${NC}" >&2
}

info() {
  echo -e "${BLUE}$1${NC}"
}

success() {
  echo -e "${GREEN}$1${NC}"
}

main() {
  echo ""
  info "Uninstalling ww (worktree workflow manager)..."
  echo ""

  local removed_something=false

  # Find and unlink symlink
  local symlink_locations=(
    "$HOME/.local/bin/ww"
    "/usr/local/bin/ww"
    "$HOME/bin/ww"
  )

  for location in "${symlink_locations[@]}"; do
    if [[ -L "$location" ]]; then
      info "Unlinking: $location"
      unlink "$location"
      removed_something=true
    elif [[ -f "$location" ]]; then
      warn "Found non-symlink at $location, skipping (remove manually if needed)"
    fi
  done

  # Remove downloaded files
  if [[ -d "$INSTALL_LOCATION" ]]; then
    info "Removing installation directory: $INSTALL_LOCATION"
    rm -rf "$INSTALL_LOCATION"
    removed_something=true
  fi

  echo ""
  if [[ "$removed_something" == true ]]; then
    success "ww has been uninstalled."
  else
    warn "Nothing to uninstall - ww was not found."
  fi

  echo ""
  info "Note: .worktrees directories and any existing branches (ww-working, etc)"
  info "in your repos were not removed. Remove them manually if needed."
}

main "$@"
