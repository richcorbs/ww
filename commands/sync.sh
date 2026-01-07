#!/usr/bin/env bash
# Sync worktree-staging with main

show_help() {
  cat <<EOF
Usage: wt sync [branch]

Sync worktree-staging with changes from another branch (default: main).
Merges the specified branch into worktree-staging to keep it up-to-date.

Arguments:
  branch    Branch to sync from (default: main)

Options:
  -h, --help    Show this help message

Examples:
  wt sync           # Sync from main
  wt sync develop   # Sync from develop branch
EOF
}

cmd_sync() {
  # Parse arguments
  local source_branch="main"

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        source_branch="$1"
        ;;
    esac
    shift
  done

  # Ensure initialized
  ensure_git_repo
  ensure_initialized

  # Ensure on worktree-staging
  local current_branch
  current_branch=$(git branch --show-current)
  if [[ "$current_branch" != "worktree-staging" ]]; then
    warn "Not on worktree-staging branch, checking it out..."
    git checkout worktree-staging
  fi

  # Check if source branch exists
  if ! git show-ref --verify --quiet "refs/heads/${source_branch}"; then
    error "Branch '${source_branch}' does not exist"
  fi

  # Check for uncommitted changes
  if has_uncommitted_changes; then
    error "You have uncommitted changes. Please commit or stash them before syncing."
  fi

  info "Syncing worktree-staging with '${source_branch}'..."

  # Fetch latest changes
  if git remote get-url origin > /dev/null 2>&1; then
    info "Fetching latest changes from origin..."
    git fetch origin 2>&1 || warn "Failed to fetch from origin"

    # Update local source branch from origin
    info "Updating local ${source_branch} from origin/${source_branch}..."
    git fetch origin "${source_branch}:${source_branch}" 2>&1 || warn "Failed to update local ${source_branch}"
  fi

  # Merge source branch into worktree-staging
  if git merge "${source_branch}" 2>&1; then
    success "Successfully synced worktree-staging with '${source_branch}'"

    # Show summary
    local merge_commit
    merge_commit=$(git rev-parse --short HEAD)
    info "Merge commit: ${merge_commit}"
  else
    error "Merge conflicts detected. Please resolve them and commit."
  fi
}
