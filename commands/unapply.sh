#!/usr/bin/env bash
# Unapply worktree commits from staging

show_help() {
  cat <<EOF
Usage: wt unapply <worktree>

Revert commits in staging that were applied from a worktree.
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

  # Get applied commits for this worktree
  local applied_commits
  applied_commits=$(get_applied_commits_for_worktree "$worktree_name")

  if [[ -z "$applied_commits" ]]; then
    info "No applied commits found for '${worktree_name}'"
    exit 0
  fi

  local commit_count
  commit_count=$(echo "$applied_commits" | wc -l | tr -d ' ')

  info "Found ${commit_count} applied commit(s) to revert"

  # Get the staging commit SHAs
  local metadata
  metadata=$(read_metadata)

  local staging_commits=()

  while IFS= read -r wt_commit; do
    local staging_commit
    staging_commit=$(echo "$metadata" | jq -r \
      --arg wc "$wt_commit" \
      '.applied_commits[$wc].staging_commit')

    if [[ -n "$staging_commit" ]] && [[ "$staging_commit" != "null" ]]; then
      staging_commits+=("$staging_commit")
    fi
  done <<< "$applied_commits"

  if [[ ${#staging_commits[@]} -eq 0 ]]; then
    warn "No staging commits found to revert"
    exit 0
  fi

  # Revert commits in reverse order (newest first)
  info "Reverting commits..."

  for ((i=${#staging_commits[@]}-1; i>=0; i--)); do
    local commit="${staging_commits[$i]}"

    local commit_msg
    commit_msg=$(git log -1 --format="%s" "$commit" 2>/dev/null || echo "unknown")

    info "Reverting: ${commit_msg}"

    if git revert --no-edit "$commit" 2>&1; then
      # Remove from metadata
      while IFS= read -r wt_commit; do
        local sc
        sc=$(echo "$metadata" | jq -r \
          --arg wc "$wt_commit" \
          '.applied_commits[$wc].staging_commit')

        if [[ "$sc" == "$commit" ]]; then
          remove_applied_commit "$wt_commit"
          break
        fi
      done <<< "$applied_commits"
    else
      error "Failed to revert commit ${commit}. Resolve conflicts and run 'git revert --continue'"
    fi
  done

  success "Unapplied ${#staging_commits[@]} commit(s) from '${worktree_name}'"
}
