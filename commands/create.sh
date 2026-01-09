#!/usr/bin/env bash
# Create a new worktree

show_help() {
  cat <<EOF
Usage: ww create <branch>

Create a new worktree with the given branch name, branching from ww-working.
The worktree name will be the same as the branch name.

Arguments:
  branch    Branch name (also used as worktree name)

Options:
  -h, --help    Show this help message

Examples:
  ww create feature/user-auth       # Creates .worktrees/feature/user-auth/
  ww create bugfix/issue-123        # Creates .worktrees/bugfix/issue-123/
  ww create feat-login              # Creates .worktrees/feat-login/
EOF
}

cmd_create() {
  # Parse arguments
  local branch=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        if [[ -z "$branch" ]]; then
          branch="$1"
        else
          error "Too many arguments"
        fi
        ;;
    esac
    shift
  done

  # Validate arguments
  if [[ -z "$branch" ]]; then
    error "Missing required argument: branch"
  fi

  # Ensure initialized
  ensure_git_repo
  ensure_initialized

  # Use branch name as worktree name
  local name="$branch"

  # Check if worktree already exists
  if worktree_exists "$name"; then
    error "Worktree '$name' already exists"
  fi

  local repo_root
  repo_root=$(get_repo_root)

  # Ensure we're on ww-working
  local current_branch
  current_branch=$(git branch --show-current)
  if [[ "$current_branch" != "ww-working" ]]; then
    warn "Not on ww-working branch, checking it out..."
    git checkout ww-working
  fi

  # Path is always .worktrees/<branch> (slashes create subdirectories)
  local worktree_path=".worktrees/${branch}"
  local abs_path="${repo_root}/${worktree_path}"

  # Create the worktree from ww-working
  info "Creating worktree '${name}'..."
  info "Branching from ww-working as '${branch}'..."

  if git worktree add -b "$branch" "$abs_path" ww-working 2>&1; then
    success "Worktree '${name}' created successfully!"
    info "Path: ${abs_path}"
    echo ""
    source "${WW_ROOT}/commands/status.sh"
    cmd_status
  else
    error "Failed to create worktree"
  fi
}
