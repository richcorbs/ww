#!/usr/bin/env bash
# Fetch latest changes from origin

show_help() {
  cat <<EOF
Usage: wt fetch

Fetch latest changes from the remote repository.
This updates your remote tracking branches (like origin/main) which allows
wt status to accurately show which worktree branches have been merged.

Options:
  -h, --help    Show this help message

Example:
  wt fetch
EOF
}

cmd_fetch() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        ;;
    esac
    shift
  done

  # Ensure we're in a git repository
  ensure_git_repo

  # Check if origin exists
  if ! git remote get-url origin > /dev/null 2>&1; then
    error "No origin remote configured"
  fi

  info "Fetching latest changes from origin..."

  if git fetch origin 2>&1; then
    success "Fetched latest changes from origin"
  else
    error "Failed to fetch from origin"
  fi
}
