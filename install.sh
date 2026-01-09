#!/usr/bin/env bash
# Installation script for ww (worktree workflow manager)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/bin"

# Check dependencies
info "Checking dependencies..."

if ! command -v git &> /dev/null; then
  error "git is required but not installed"
fi

if ! command -v jq &> /dev/null; then
  error "jq is required but not installed. Install it with: brew install jq"
fi

# Check git version
GIT_VERSION=$(git --version | awk '{print $3}')
MIN_GIT_VERSION="2.5.0"

if ! printf '%s\n%s\n' "$MIN_GIT_VERSION" "$GIT_VERSION" | sort -V -C; then
  error "git version $MIN_GIT_VERSION or higher is required (found $GIT_VERSION)"
fi

success "All required dependencies satisfied"

# Check for optional dependencies
if ! command -v fzf &> /dev/null; then
  warn "fzf is not installed (optional but highly recommended)"
  info "fzf enables interactive file and worktree selection"
  info ""
  info "Install fzf with:"
  info "  macOS:   brew install fzf"
  info "  Ubuntu:  sudo apt install fzf"
  info "  Fedora:  sudo dnf install fzf"
  info "  Manual:  https://github.com/junegunn/fzf#installation"
  echo ""
else
  success "fzf is installed"
fi

if ! command -v gh &> /dev/null; then
  warn "gh (GitHub CLI) is not installed (optional)"
  info "gh enables PR links in status and 'ww pr' command"
  info ""
  info "Install gh with:"
  info "  macOS:   brew install gh"
  info "  Ubuntu:  See https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
  info "  Manual:  https://github.com/cli/cli#installation"
  echo ""
else
  success "gh (GitHub CLI) is installed"
fi

# Determine installation directory
info ""
info "Determining installation location..."

INSTALL_DIR=""

# Check common locations in order of preference
if [[ -d "$HOME/.local/bin" ]]; then
  INSTALL_DIR="$HOME/.local/bin"
elif [[ -d "/usr/local/bin" ]] && [[ -w "/usr/local/bin" ]]; then
  INSTALL_DIR="/usr/local/bin"
elif [[ -d "$HOME/bin" ]]; then
  INSTALL_DIR="$HOME/bin"
else
  # Create ~/.local/bin
  mkdir -p "$HOME/.local/bin"
  INSTALL_DIR="$HOME/.local/bin"
fi

info "Installing to: ${INSTALL_DIR}"

# Check if directory is in PATH
if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
  warn "${INSTALL_DIR} is not in your PATH"
  info "Add this to your ~/.bashrc or ~/.zshrc:"
  info "  export PATH=\"${INSTALL_DIR}:\$PATH\""
  echo ""
fi

# Create symlink
info "Creating symlink..."

if [[ -L "${INSTALL_DIR}/ww" ]] || [[ -f "${INSTALL_DIR}/ww" ]]; then
  warn "${INSTALL_DIR}/ww already exists"

  read -rp "Overwrite? (y/N) " response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    info "Installation cancelled"
    exit 0
  fi

  rm -f "${INSTALL_DIR}/ww"
fi

ln -s "${BIN_DIR}/ww" "${INSTALL_DIR}/ww"

success "Symlink created: ${INSTALL_DIR}/ww -> ${BIN_DIR}/ww"

# Verify installation
info ""
info "Verifying installation..."

if command -v ww &> /dev/null; then
  success "Installation successful!"
  echo ""
  info "Try running:"
  info "  ww --help"
  echo ""
  info "To get started in a git repository:"
  info "  ww init"
else
  error "Installation failed. ww command not found in PATH."
fi
