#!/usr/bin/env bash
# Commit changes in a worktree

show_help() {
  cat <<EOF
Usage: wt commit <worktree> <message>

Commit changes in a worktree without having to cd into it.

Arguments:
  worktree    Name of the worktree
  message     Commit message

Options:
  -h, --help    Show this help message

Examples:
  wt commit feature-auth "Add user authentication"
  wt commit bugfix-123 "Fix login issue"
EOF
}

cmd_commit() {
  # Parse arguments
  local worktree_name=""
  local commit_message=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        if [[ -z "$worktree_name" ]]; then
          worktree_name="$1"
        elif [[ -z "$commit_message" ]]; then
          commit_message="$1"
        else
          # Allow multi-word commit messages
          commit_message="${commit_message} $1"
        fi
        ;;
    esac
    shift
  done

  # Validate arguments
  if [[ -z "$worktree_name" ]]; then
    error "Missing required argument: worktree"
  fi

  if [[ -z "$commit_message" ]]; then
    error "Missing required argument: message"
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

  local abs_worktree_path="${repo_root}/${worktree_path}"

  # Enter worktree and commit
  info "Committing changes in '${worktree_name}'..."

  if pushd "$abs_worktree_path" > /dev/null 2>&1; then
    # Check if there are changes to commit
    if ! has_uncommitted_changes; then
      popd > /dev/null 2>&1
      warn "No changes to commit in '${worktree_name}'"
      exit 0
    fi

    # Stage all changes and commit
    if git add -A && git commit -m "$commit_message" 2>&1; then
      local commit_sha
      commit_sha=$(git rev-parse HEAD)
      local short_sha
      short_sha=$(git rev-parse --short HEAD)

      popd > /dev/null 2>&1

      success "Changes committed in '${worktree_name}'"
      info "Commit: ${short_sha}"
      info "Message: ${commit_message}"
    else
      popd > /dev/null 2>&1
      error "Failed to commit changes"
    fi
  else
    error "Failed to enter worktree directory"
  fi
}
