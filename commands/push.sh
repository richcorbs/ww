#!/usr/bin/env bash
# Push a worktree branch to remote

show_help() {
  cat <<EOF
Usage: wt push <worktree>

Push the worktree's branch to the remote repository.
Sets upstream if not already configured.

Arguments:
  worktree    Name of the worktree

Options:
  -h, --help    Show this help message

Example:
  wt push feature-auth
EOF
}

cmd_push() {
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

  verify_worktree_exists "$worktree_name"

  local repo_root
  repo_root=$(get_repo_root)

  local worktree_path
  worktree_path=$(get_worktree_path "$worktree_name")

  local worktree_branch
  worktree_branch=$(get_worktree_branch "$worktree_name")

  local abs_worktree_path="${repo_root}/${worktree_path}"

  # Enter worktree and push
  info "Pushing '${worktree_branch}' to origin..."

  if pushd "$abs_worktree_path" > /dev/null 2>&1; then
    # Check if upstream is set
    local upstream
    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "")

    if [[ -z "$upstream" ]]; then
      # Set upstream and push
      if git push -u origin "$worktree_branch" 2>&1; then
        success "Branch '${worktree_branch}' pushed and upstream set"
      else
        popd > /dev/null 2>&1
        error "Failed to push branch"
      fi
    else
      # Just push
      if git push 2>&1; then
        success "Branch '${worktree_branch}' pushed"
      else
        popd > /dev/null 2>&1
        error "Failed to push branch"
      fi
    fi

    popd > /dev/null 2>&1
  else
    error "Failed to enter worktree directory"
  fi
}
