#!/usr/bin/env bash
# Uncommit the last commit in a worktree

show_help() {
  cat <<EOF
Usage: wt uncommit <worktree>

Uncommit the last commit in a worktree by resetting by one commit.
Brings the changes back to uncommitted state in that worktree.

Arguments:
  worktree    Name of the worktree

Options:
  -h, --help    Show this help message

Example:
  wt uncommit feature-auth
EOF
}

cmd_uncommit() {
  # Parse arguments
  local worktree_name=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        if [[ -z "$worktree_name" ]]; then
          worktree_name="$1"
        else
          error "Too many arguments"
        fi
        ;;
    esac
    shift
  done

  # Ensure initialized
  ensure_git_repo
  ensure_initialized

  # Validate arguments - use fzf if worktree not provided
  if [[ -z "$worktree_name" ]]; then
    worktree_name=$(select_worktree_interactive)
    if [[ -z "$worktree_name" ]]; then
      error "No worktree selected"
    fi
  fi

  # Check if worktree exists

  # Check if worktree exists
  if ! worktree_exists "$worktree_name"; then
    error "Worktree '$worktree_name' not found"
  fi

  verify_worktree_exists "$worktree_name"

  local repo_root
  repo_root=$(get_repo_root)

  local worktree_path
  worktree_path=$(get_worktree_path "$worktree_name")

  local abs_worktree_path="${repo_root}/${worktree_path}"

  # Enter worktree and undo
  if pushd "$abs_worktree_path" > /dev/null 2>&1; then
    # Check if there are commits to undo
    local commit_count
    commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")

    if [[ "$commit_count" -eq 0 ]]; then
      popd > /dev/null 2>&1
      warn "No commits to uncommit in '${worktree_name}'"
      exit 0
    fi

    # Get the last commit info
    local last_commit_msg
    last_commit_msg=$(git log -1 --format="%s")

    local last_commit_sha
    last_commit_sha=$(git rev-parse --short HEAD)

    info "Last commit in '${worktree_name}': ${last_commit_sha} - ${last_commit_msg}"

    # Ask for confirmation
    read -rp "Uncommit this commit? (y/N) " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      popd > /dev/null 2>&1
      info "Uncommit cancelled"
      exit 0
    fi

    # Reset to previous commit, keeping changes
    if git reset HEAD~1 2>&1; then
      popd > /dev/null 2>&1
      success "Uncommitted last commit in '${worktree_name}': ${last_commit_sha}"
      info "Changes are now uncommitted in the worktree"
      echo ""
      source "${WT_ROOT}/commands/status.sh"
      cmd_status
    else
      popd > /dev/null 2>&1
      error "Failed to uncommit"
    fi
  else
    error "Failed to enter worktree directory"
  fi
}
