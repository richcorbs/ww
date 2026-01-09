#!/usr/bin/env bash
# Installation script for ww (worktree workflow manager)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/richcorbs/ww/main/install.sh | bash
#
#   Or from a cloned repo:
#   ./install.sh
#   ./install.sh --local  # Force local mode (symlink to repo)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_URL="https://github.com/richcorbs/ww.git"
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

# Check if running from curl (stdin is not a terminal and no local files)
is_curl_install() {
  # If --local flag is passed, force local mode
  if [[ "${1:-}" == "--local" ]]; then
    return 1
  fi

  # Check if we're in a directory with the ww source
  if [[ -f "bin/ww" ]] && [[ -f "lib/ww-lib.sh" ]]; then
    return 1  # Local install
  fi

  return 0  # Curl install
}

check_dependencies() {
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
}

get_bin_dir() {
  local install_dir=""

  # Check common locations in order of preference
  if [[ -d "$HOME/.local/bin" ]]; then
    install_dir="$HOME/.local/bin"
  elif [[ -d "/usr/local/bin" ]] && [[ -w "/usr/local/bin" ]]; then
    install_dir="/usr/local/bin"
  elif [[ -d "$HOME/bin" ]]; then
    install_dir="$HOME/bin"
  else
    # Create ~/.local/bin
    mkdir -p "$HOME/.local/bin"
    install_dir="$HOME/.local/bin"
  fi

  echo "$install_dir"
}

check_path() {
  local install_dir="$1"

  if [[ ":$PATH:" != *":${install_dir}:"* ]]; then
    warn "${install_dir} is not in your PATH"
    info "Add this to your ~/.bashrc or ~/.zshrc:"
    info "  export PATH=\"${install_dir}:\$PATH\""
    echo ""
  fi
}

create_symlink() {
  local source_bin="$1"
  local install_dir="$2"

  info "Creating symlink..."

  if [[ -L "${install_dir}/ww" ]] || [[ -f "${install_dir}/ww" ]]; then
    local existing_target
    existing_target=$(readlink "${install_dir}/ww" 2>/dev/null || echo "unknown")
    warn "${install_dir}/ww already exists (-> ${existing_target})"

    # If running non-interactively (curl), auto-overwrite
    if [[ ! -t 0 ]]; then
      info "Overwriting existing installation..."
      rm -f "${install_dir}/ww"
    else
      read -rp "Overwrite? (y/N) " response
      if [[ ! "$response" =~ ^[Yy]$ ]]; then
        info "Installation cancelled"
        exit 0
      fi
      rm -f "${install_dir}/ww"
    fi
  fi

  ln -s "${source_bin}" "${install_dir}/ww"
  success "Symlink created: ${install_dir}/ww -> ${source_bin}"
}

verify_installation() {
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
    warn "ww command not found in PATH (you may need to restart your shell)"
    info ""
    info "Try running:"
    info "  ~/.local/bin/ww --help"
  fi
}

# Main installation
main() {
  echo ""
  info "Installing ww (worktree workflow manager)..."
  echo ""

  check_dependencies

  local bin_dir
  bin_dir=$(get_bin_dir)

  info ""
  info "Installing to: ${bin_dir}"

  check_path "$bin_dir"

  if is_curl_install "${1:-}"; then
    # Curl install: download to ~/.local/share/ww
    info "Downloading ww..."

    if [[ -d "$INSTALL_LOCATION" ]]; then
      info "Updating existing installation..."
      if pushd "$INSTALL_LOCATION" > /dev/null 2>&1; then
        git pull --quiet origin main 2>/dev/null || {
          warn "Could not update, reinstalling..."
          popd > /dev/null 2>&1
          rm -rf "$INSTALL_LOCATION"
          git clone --quiet "$REPO_URL" "$INSTALL_LOCATION"
        }
        popd > /dev/null 2>&1 || true
      fi
    else
      mkdir -p "$(dirname "$INSTALL_LOCATION")"
      git clone --quiet "$REPO_URL" "$INSTALL_LOCATION"
    fi

    success "Downloaded to ${INSTALL_LOCATION}"
    create_symlink "${INSTALL_LOCATION}/bin/ww" "$bin_dir"
  else
    # Local install: symlink to current repo
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    info "Installing from local repo: ${script_dir}"
    create_symlink "${script_dir}/bin/ww" "$bin_dir"
  fi

  verify_installation
}

main "$@"
