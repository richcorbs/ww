#!/usr/bin/env bash
# Initialize worktree workflow in current repository

show_help() {
  cat <<EOF
Usage: wt init

Initialize the worktree workflow in the current git repository.

This will:
  - Create/checkout worktree-staging branch
  - Create .worktree-flow/ directory for metadata
  - Create initial metadata.json file
  - Create initial abbreviations.json file
  - Add .worktree-flow/ to .gitignore

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

  # Create or checkout worktree-staging branch
  local current_branch
  current_branch=$(git branch --show-current)

  # Create .worktree-flow directory
  mkdir -p "${repo_root}/${WT_FLOW_DIR}"
  success "Created .worktree-flow directory"

  # Create .worktrees directory
  mkdir -p "${repo_root}/.worktrees"
  success "Created .worktrees directory"

  # Create initial metadata.json
  echo '{"worktrees": {}, "applied_commits": {}}' | jq '.' > "${repo_root}/${METADATA_FILE}"
  echo '{}' | jq '.' > "${repo_root}/${ABBREV_FILE}"

  # Add to .gitignore
  local gitignore="${repo_root}/.gitignore"
  local gitignore_updated=false

  if [[ -f "$gitignore" ]]; then
    if ! grep -q "^${WT_FLOW_DIR}/" "$gitignore" 2>/dev/null; then
      echo "${WT_FLOW_DIR}/" >> "$gitignore"
      gitignore_updated=true
    fi
    if ! grep -q "^\.worktrees/" "$gitignore" 2>/dev/null; then
      echo ".worktrees/" >> "$gitignore"
      gitignore_updated=true
    fi
  else
    echo "${WT_FLOW_DIR}/" > "$gitignore"
    echo ".worktrees/" >> "$gitignore"
    gitignore_updated=true
  fi

  if [[ "$gitignore_updated" == "true" ]]; then
    success "Updated .gitignore"
  fi

  # Commit .gitignore if it was created or updated
  if [[ "$gitignore_updated" == "true" ]]; then
    git add .gitignore
    git commit -m "wt: Initialize workflow (add .gitignore entries)" > /dev/null 2>&1 || true
  fi

  # Create or checkout worktree-staging branch
  if git show-ref --verify --quiet refs/heads/worktree-staging; then
    # Branch exists, check it out
    git checkout worktree-staging > /dev/null 2>&1
    success "Checked out worktree-staging branch"
  else
    # Create new branch from current branch
    git checkout -b worktree-staging > /dev/null 2>&1
    success "Created worktree-staging branch"
    success "Checked out worktree-staging branch"
  fi

  success "Worktree workflow initialized"
}
