#!/usr/bin/env bash
# Apply worktree commits to staging

show_help() {
  cat <<EOF
Usage: wt apply <worktree>

Apply (cherry-pick) all commits from a worktree that haven't been
applied to staging yet. This makes those changes unavailable for
other worktrees.

Arguments:
  worktree    Name of the worktree

Options:
  -h, --help    Show this help message

Example:
  wt apply feature-auth
EOF
}

cmd_apply() {
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

  # Get commits from worktree that aren't in current branch
  info "Finding commits to apply from '${worktree_name}'..."

  local current_branch
  current_branch=$(git branch --show-current)

  # Get list of commits in worktree branch but not in current branch
  # Use --reverse to get oldest first (for cherry-picking in order)
  local commits
  commits=$(git rev-list --reverse "${current_branch}..${worktree_branch}" 2>/dev/null || true)

  if [[ -z "$commits" ]]; then
    info "No new commits to apply from '${worktree_name}'"
    exit 0
  fi

  local commit_count
  commit_count=$(echo "$commits" | wc -l | tr -d ' ')

  info "Found ${commit_count} commit(s) to apply"

  # Cherry-pick each commit
  local applied_commits=()

  while IFS= read -r commit; do
    local commit_msg
    commit_msg=$(git log -1 --format="%s" "$commit")

    info "Applying: ${commit_msg}"

    if git cherry-pick "$commit" 2>&1; then
      local new_commit
      new_commit=$(git rev-parse HEAD)

      # Track the applied commit
      add_applied_commit "$commit" "$new_commit" "$worktree_name"

      applied_commits+=("$commit")
    else
      error "Failed to apply commit ${commit}. Resolve conflicts and run 'git cherry-pick --continue'"
    fi
  done <<< "$commits"

  success "Applied ${#applied_commits[@]} commit(s) from '${worktree_name}' to staging"
  echo ""
  source "${WT_ROOT}/commands/status.sh"
  cmd_status
}
