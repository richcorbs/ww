#!/usr/bin/env bash
# Shared library functions for worktree workflow scripts

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Constants
readonly WT_FLOW_DIR=".worktree-flow"
readonly METADATA_FILE="${WT_FLOW_DIR}/metadata.json"
readonly ABBREV_FILE="${WT_FLOW_DIR}/abbreviations.json"

# Error handling
error() {
  echo -e "  ${RED}Error: $1${NC}" >&2
  exit 1
}

warn() {
  echo -e "  ${YELLOW}Warning: $1${NC}" >&2
}

info() {
  echo -e "  ${BLUE}$1${NC}"
}

success() {
  echo -e "  ${GREEN}$1${NC}"
}

# Git repository checks
ensure_git_repo() {
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not a git repository. Please run this command from within a git repository."
  fi
}

get_repo_root() {
  git rev-parse --show-toplevel
}

# Check if worktree-flow is initialized
is_initialized() {
  local repo_root
  repo_root=$(get_repo_root)
  [[ -d "${repo_root}/${WT_FLOW_DIR}" ]]
}

ensure_initialized() {
  if ! is_initialized; then
    error "Worktree workflow not initialized. Run 'wt-init' first."
  fi
}

# Metadata file operations
metadata_exists() {
  local repo_root
  repo_root=$(get_repo_root)
  [[ -f "${repo_root}/${METADATA_FILE}" ]]
}

read_metadata() {
  local repo_root
  repo_root=$(get_repo_root)

  if ! metadata_exists; then
    echo '{}'
    return
  fi

  cat "${repo_root}/${METADATA_FILE}"
}

write_metadata() {
  local data="$1"
  local repo_root
  repo_root=$(get_repo_root)

  echo "$data" | jq '.' > "${repo_root}/${METADATA_FILE}"
}

# Get worktree info from metadata
get_worktree_info() {
  local name="$1"
  local field="${2:-}"

  local metadata
  metadata=$(read_metadata)

  if [[ -z "$field" ]]; then
    echo "$metadata" | jq -r ".worktrees[\"$name\"] // {}"
  else
    echo "$metadata" | jq -r ".worktrees[\"$name\"].${field} // empty"
  fi
}

# Check if worktree exists in metadata
worktree_exists() {
  local name="$1"
  local info
  info=$(get_worktree_info "$name")
  [[ "$info" != "{}" ]]
}

# Add worktree to metadata
add_worktree_metadata() {
  local name="$1"
  local branch="$2"
  local path="$3"
  local created
  created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local metadata
  metadata=$(read_metadata)

  metadata=$(echo "$metadata" | jq \
    --arg name "$name" \
    --arg branch "$branch" \
    --arg path "$path" \
    --arg created "$created" \
    '.worktrees[$name] = {branch: $branch, path: $path, created: $created}')

  write_metadata "$metadata"
}

# Remove worktree from metadata
remove_worktree_metadata() {
  local name="$1"

  local metadata
  metadata=$(read_metadata)

  metadata=$(echo "$metadata" | jq --arg name "$name" 'del(.worktrees[$name])')

  write_metadata "$metadata"
}

# Get all worktree names from metadata
list_worktree_names() {
  local metadata
  metadata=$(read_metadata)

  echo "$metadata" | jq -r '.worktrees | keys[]' 2>/dev/null || true
}

# Applied commits tracking
add_applied_commit() {
  local worktree_commit="$1"
  local staging_commit="$2"
  local worktree="$3"
  local applied_at
  applied_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local metadata
  metadata=$(read_metadata)

  metadata=$(echo "$metadata" | jq \
    --arg wc "$worktree_commit" \
    --arg sc "$staging_commit" \
    --arg wt "$worktree" \
    --arg at "$applied_at" \
    '.applied_commits[$wc] = {worktree: $wt, staging_commit: $sc, applied_at: $at}')

  write_metadata "$metadata"
}

remove_applied_commit() {
  local worktree_commit="$1"

  local metadata
  metadata=$(read_metadata)

  metadata=$(echo "$metadata" | jq --arg wc "$worktree_commit" 'del(.applied_commits[$wc])')

  write_metadata "$metadata"
}

get_applied_commits_for_worktree() {
  local worktree="$1"

  local metadata
  metadata=$(read_metadata)

  echo "$metadata" | jq -r \
    --arg wt "$worktree" \
    '.applied_commits | to_entries[] | select(.value.worktree == $wt) | .key' 2>/dev/null || true
}

# Check if on protected branch
is_protected_branch() {
  local branch
  branch=$(git branch --show-current)

  [[ "$branch" == "main" ]] || [[ "$branch" == "master" ]]
}

ensure_not_protected_branch() {
  if is_protected_branch; then
    error "Cannot perform this operation on main/master branch"
  fi
}

# Check for uncommitted changes
has_uncommitted_changes() {
  # Check for modified/staged files
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    return 0
  fi

  # Check for untracked files
  if [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
    return 0
  fi

  return 1
}

# Get worktree path from name
get_worktree_path() {
  local name="$1"
  get_worktree_info "$name" "path"
}

# Get worktree branch from name
get_worktree_branch() {
  local name="$1"
  get_worktree_info "$name" "branch"
}

# Verify worktree directory exists
verify_worktree_exists() {
  local name="$1"
  local path
  path=$(get_worktree_path "$name")

  if [[ -z "$path" ]]; then
    error "Worktree '$name' not found in metadata"
  fi

  local repo_root
  repo_root=$(get_repo_root)
  local full_path="${repo_root}/${path}"

  if [[ ! -d "$full_path" ]]; then
    error "Worktree directory '$full_path' does not exist"
  fi
}
