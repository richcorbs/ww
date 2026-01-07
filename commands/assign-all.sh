#!/usr/bin/env bash
# Assign all uncommitted changes to a worktree

show_help() {
  cat <<EOF
Usage: wt assign-all <worktree>

Assign all uncommitted changes to a worktree and commit them to worktree-staging.
Useful for starting a new feature with all current work.

Arguments:
  worktree    Name of the worktree

Options:
  -h, --help    Show this help message

Example:
  wt assign-all feature-auth
EOF
}

cmd_assign_all() {
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

  # Validate arguments
  if [[ -z "$worktree_name" ]]; then
    error "Missing required argument: worktree"
  fi

  # Ensure initialized
  ensure_git_repo
  ensure_initialized

  # Check if worktree exists
  if ! worktree_exists "$worktree_name"; then
    error "Worktree '$worktree_name' not found"
  fi

  # Check if there are uncommitted changes
  if ! has_uncommitted_changes; then
    warn "No uncommitted changes to assign"
    exit 0
  fi

  # Get worktree path
  verify_worktree_exists "$worktree_name"

  local repo_root
  repo_root=$(get_repo_root)

  local worktree_path
  worktree_path=$(get_worktree_path "$worktree_name")

  local abs_worktree_path="${repo_root}/${worktree_path}"

  # Stage and commit all changes to worktree-staging
  info "Committing all changes to worktree-staging..."

  git add -A

  if git commit -m "wt: assign all changes to ${worktree_name}" 2>&1; then
    local commit_sha
    commit_sha=$(git rev-parse HEAD)
    local short_sha
    short_sha=$(git rev-parse --short HEAD)

    info "Committed as ${short_sha}"

    # Create patch from the commit
    local patch_file
    patch_file=$(mktemp)
    git show "$commit_sha" > "$patch_file"

    # Apply to worktree
    info "Applying changes to worktree '${worktree_name}'..."

    if pushd "$abs_worktree_path" > /dev/null 2>&1; then
      # Apply the patch
      if git apply "$patch_file" 2>&1; then
        popd > /dev/null 2>&1
        rm -f "$patch_file"
        success "All changes assigned to '${worktree_name}' and committed to worktree-staging"
      else
        popd > /dev/null 2>&1
        rm -f "$patch_file"
        warn "Failed to apply some changes to worktree, but committed to worktree-staging"
      fi
    else
      rm -f "$patch_file"
      warn "Failed to enter worktree directory, but changes are committed to worktree-staging"
    fi
  else
    error "Failed to commit changes to worktree-staging"
  fi
}
