#!/usr/bin/env bash
# Unapply worktree commits from wt-working

show_help() {
  cat <<EOF
Usage: wt unapply <worktree>

Revert assignment commits in wt-working that were made for a worktree.
Uses 'git revert' to preserve history safely.

Arguments:
  worktree    Name of the worktree

Options:
  -h, --help    Show this help message

Example:
  wt unapply feature-auth
EOF
}

cmd_unapply() {
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

  # Find assignment commits for this worktree in wt-working
  info "Finding assignment commits for '${worktree_name}'..."

  local assignment_commits=()
  while IFS= read -r sha; do
    if [[ -n "$sha" ]]; then
      assignment_commits+=("$sha")
    fi
  done < <(git log --format="%H" --grep="wt: assign .* to ${worktree_name}$" wt-working --max-count=100 2>/dev/null)

  if [[ ${#assignment_commits[@]} -eq 0 ]]; then
    info "No assignment commits found for '${worktree_name}'"
    exit 0
  fi

  info "Found ${#assignment_commits[@]} assignment commit(s) to revert"

  # Ensure on wt-working branch
  local current_branch
  current_branch=$(git branch --show-current)
  if [[ "$current_branch" != "wt-working" ]]; then
    error "Must be on wt-working branch to unapply. Current branch: ${current_branch}"
  fi

  # Revert each commit (in reverse order, newest first)
  local reverted=0
  for commit in "${assignment_commits[@]}"; do
    local commit_msg
    commit_msg=$(git log -1 --format="%s" "$commit" 2>/dev/null || echo "unknown")

    info "Reverting: ${commit_msg}"

    if git revert --no-edit "$commit" 2>&1; then
      reverted=$((reverted + 1))
    else
      error "Failed to revert commit ${commit}. Resolve conflicts and run 'git revert --continue'"
    fi
  done

  success "Unapplied ${reverted} commit(s) from '${worktree_name}'"
  echo ""
  source "${WT_ROOT}/commands/status.sh"
  cmd_status
}
