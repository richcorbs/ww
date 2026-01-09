#!/usr/bin/env bash
# Initialize worktree workflow in current repository

show_help() {
  cat <<EOF
Usage: ww init

Initialize the worktree workflow in the current git repository.

This will:
  - Create ww-working branch from main
  - Create .worktrees/ directory for feature worktrees
  - Add .worktrees/ to .gitignore

Options:
  -h, --help    Show this help message
EOF
}

cmd_init() {
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

  # Check if already initialized
  if is_initialized; then
    warn "Worktree workflow already initialized in this repository"
    exit 0
  fi

  local repo_root
  repo_root=$(get_repo_root)

  # Create .worktrees directory
  mkdir -p "${repo_root}/.worktrees"
  success "Created .worktrees directory"

  # Add to .gitignore
  local gitignore="${repo_root}/.gitignore"
  local gitignore_updated=false

  if [[ -f "$gitignore" ]]; then
    if ! grep -q "^\.worktrees/" "$gitignore" 2>/dev/null; then
      echo ".worktrees/" >> "$gitignore"
      gitignore_updated=true
    fi
  else
    echo ".worktrees/" > "$gitignore"
    gitignore_updated=true
  fi

  if [[ "$gitignore_updated" == "true" ]]; then
    success "Updated .gitignore"
    git add .gitignore
    git commit -m "ww: Initialize workflow (add .worktrees/ to .gitignore)" > /dev/null 2>&1 || true
  fi

  # Ensure main branch exists
  if ! git show-ref --verify --quiet refs/heads/main; then
    error "Main branch does not exist. Please create it first or ensure you have a main branch."
  fi

  # Create or checkout ww-working branch
  if git show-ref --verify --quiet refs/heads/ww-working; then
    # Branch exists, check it out
    git checkout ww-working > /dev/null 2>&1
    success "Checked out ww-working branch"
  else
    # Create new branch from main
    git checkout -b ww-working main > /dev/null 2>&1
    success "Created ww-working branch from main"
    success "Checked out ww-working branch"
  fi

  success "Worktree workflow initialized"
}
