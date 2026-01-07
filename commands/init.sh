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

  if git show-ref --verify --quiet refs/heads/worktree-staging; then
    # Branch exists, check it out
    info "Checking out existing worktree-staging branch..."
    git checkout worktree-staging
  else
    # Create new branch from current branch
    info "Creating worktree-staging branch from ${current_branch}..."
    git checkout -b worktree-staging
  fi

  # Create .worktree-flow directory
  info "Creating ${WT_FLOW_DIR} directory..."
  mkdir -p "${repo_root}/${WT_FLOW_DIR}"

  # Create initial metadata.json
  info "Creating metadata files..."
  echo '{"worktrees": {}, "applied_commits": {}}' | jq '.' > "${repo_root}/${METADATA_FILE}"
  echo '{}' | jq '.' > "${repo_root}/${ABBREV_FILE}"

  # Add to .gitignore
  local gitignore="${repo_root}/.gitignore"
  if [[ -f "$gitignore" ]]; then
    if ! grep -q "^${WT_FLOW_DIR}/" "$gitignore" 2>/dev/null; then
      info "Adding ${WT_FLOW_DIR}/ to .gitignore..."
      echo "${WT_FLOW_DIR}/" >> "$gitignore"
    fi
    if ! grep -q "^\.worktrees/" "$gitignore" 2>/dev/null; then
      info "Adding .worktrees/ to .gitignore..."
      echo ".worktrees/" >> "$gitignore"
    fi
  else
    info "Creating .gitignore..."
    echo "${WT_FLOW_DIR}/" > "$gitignore"
    echo ".worktrees/" >> "$gitignore"
  fi

  success "Worktree workflow initialized successfully!"
  info "Working in worktree-staging branch"
  info "You can now use 'wt create' to create worktrees"
}
