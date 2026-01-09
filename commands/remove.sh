#!/usr/bin/env bash
# Remove a worktree

show_help() {
  cat <<EOF
Usage: ww remove <worktree> [--force]

Remove a worktree and clean up metadata.
Warns if the branch has unpushed commits unless --force is used.

Arguments:
  worktree    Name of the worktree to remove

Options:
  -f, --force   Force removal even with unpushed commits
  -h, --help    Show this help message

Example:
  ww remove feature-auth
  ww remove feature-auth --force
EOF
}

cmd_remove() {
  # Parse arguments
  local worktree_name=""
  local force=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      -f|--force)
        force=true
        ;;
      *)
        if [[ -z "$worktree_name" ]]; then
          worktree_name="$1"
        else
          error "Unknown argument: $1"
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
  if ! worktree_exists "$worktree_name"; then
    error "Worktree '$worktree_name' not found"
  fi

  local repo_root
  repo_root=$(get_repo_root)

  local worktree_path
  worktree_path=$(get_worktree_path "$worktree_name")

  local worktree_branch
  worktree_branch=$(get_worktree_branch "$worktree_name")

  local abs_worktree_path="${repo_root}/${worktree_path}"

  # Check if directory exists
  if [[ ! -d "$abs_worktree_path" ]]; then
    warn "Worktree directory not found at ${abs_worktree_path}"
    warn "Cleaning up git worktree registration..."

    git worktree prune

    # Try to delete the branch if it exists
    if git show-ref --verify --quiet "refs/heads/${worktree_branch}"; then
      git branch -D "$worktree_branch" 2>/dev/null || true
    fi

    success "Cleaned up worktree registration for '${worktree_name}'"
    exit 0
  fi

  # Check for unpushed commits if not forcing
  if [[ "$force" == "false" ]]; then
    if pushd "$abs_worktree_path" > /dev/null 2>&1; then
      local upstream
      upstream=$(get_upstream_branch)

      if [[ -n "$upstream" ]]; then
        local ahead behind
        while IFS=' ' read -r key value; do
          if [[ "$key" == "ahead" ]]; then
            ahead="$value"
          fi
        done < <(get_ahead_behind_counts)

        if [[ "$ahead" -gt 0 ]]; then
          popd > /dev/null 2>&1
          error "Branch '${worktree_branch}' has ${ahead} unpushed commit(s). Use --force to remove anyway."
        fi
      fi

      # Check for uncommitted changes
      if has_uncommitted_changes; then
        popd > /dev/null 2>&1
        warn "Worktree has uncommitted changes"

        read -rp "Continue with removal? (y/N) " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
          info "Removal cancelled"
          exit 0
        fi
      fi

      popd > /dev/null 2>&1
    fi
  fi

  # Remove the worktree
  info "Removing worktree '${worktree_name}'..."

  if git worktree remove "$abs_worktree_path" 2>&1 || git worktree remove --force "$abs_worktree_path" 2>&1; then
    success "Worktree '${worktree_name}' removed"
  else
    error "Failed to remove worktree"
  fi
}
