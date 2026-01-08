#!/usr/bin/env bash
# Switch between worktree-staging and main

show_help() {
  cat <<EOF
Usage: wt switch [branch]

Switch between branches. If no branch is specified:
  - If on worktree-staging: switch to main
  - If on any other branch: switch to worktree-staging

Arguments:
  branch    Optional branch name to switch to

Options:
  -h, --help    Show this help message

Examples:
  wt switch              # Toggle between worktree-staging and main
  wt switch develop      # Switch to develop branch
EOF
}

cmd_switch() {
  # Parse arguments
  local target_branch=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        if [[ -z "$target_branch" ]]; then
          target_branch="$1"
        else
          error "Too many arguments"
        fi
        ;;
    esac
    shift
  done

  # Ensure we're in a git repository
  ensure_git_repo

  # Get current branch
  local current_branch
  current_branch=$(git branch --show-current)

  # If no target specified, toggle between worktree-staging and main
  if [[ -z "$target_branch" ]]; then
    if [[ "$current_branch" == "worktree-staging" ]]; then
      # Determine main branch name
      local main_branch="main"
      if git show-ref --verify --quiet refs/heads/master; then
        main_branch="master"
      fi
      target_branch="$main_branch"
    else
      target_branch="worktree-staging"
    fi
  fi

  # Check if target branch exists
  if ! git show-ref --verify --quiet "refs/heads/${target_branch}"; then
    error "Branch '${target_branch}' does not exist"
  fi

  # Check if already on target branch
  if [[ "$current_branch" == "$target_branch" ]]; then
    info "Already on branch '${target_branch}'"
    exit 0
  fi

  # Check for uncommitted changes
  if has_uncommitted_changes; then
    warn "You have uncommitted changes"
    info "Please commit or stash them before switching branches"
    exit 1
  fi

  # Switch branch
  if git checkout "$target_branch" 2>&1; then
    success "Switched to branch '${target_branch}'"
  else
    error "Failed to switch to branch '${target_branch}'"
  fi
}
