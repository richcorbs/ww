#!/usr/bin/env bash
# Create a new worktree

show_help() {
  cat <<EOF
Usage: wt create <name> <branch> [path]

Create a new worktree with the given name and branch, branching from worktree-staging.

Arguments:
  name      Name for the worktree (used to reference it)
  branch    Branch name for the worktree
  path      Optional custom path (default: .worktrees/<name>)

Options:
  -h, --help    Show this help message

Examples:
  wt create feature-auth feature/user-auth
  wt create bugfix-123 bugfix/issue-123 ~/my-worktrees/bugfix
EOF
}

cmd_create() {
  # Parse arguments
  local name=""
  local branch=""
  local custom_path=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"
        elif [[ -z "$branch" ]]; then
          branch="$1"
        elif [[ -z "$custom_path" ]]; then
          custom_path="$1"
        else
          error "Too many arguments"
        fi
        ;;
    esac
    shift
  done

  # Validate arguments
  if [[ -z "$name" ]]; then
    error "Missing required argument: name"
  fi

  if [[ -z "$branch" ]]; then
    error "Missing required argument: branch"
  fi

  # Ensure initialized
  ensure_git_repo
  ensure_initialized

  # Check if worktree already exists
  if worktree_exists "$name"; then
    error "Worktree '$name' already exists"
  fi

  local repo_root
  repo_root=$(get_repo_root)

  # Ensure we're on worktree-staging
  local current_branch
  current_branch=$(git branch --show-current)
  if [[ "$current_branch" != "worktree-staging" ]]; then
    warn "Not on worktree-staging branch, checking it out..."
    git checkout worktree-staging
  fi

  # Determine path
  local worktree_path
  if [[ -n "$custom_path" ]]; then
    worktree_path="$custom_path"
  else
    worktree_path=".worktrees/${name}"
  fi

  # Convert to absolute path for git worktree add
  local abs_path
  if [[ "$worktree_path" = /* ]]; then
    abs_path="$worktree_path"
  else
    abs_path="${repo_root}/${worktree_path}"
  fi

  # Create the worktree from worktree-staging
  info "Creating worktree '${name}' at ${abs_path}..."
  info "Branching from worktree-staging..."

  if git worktree add -b "$branch" "$abs_path" worktree-staging 2>&1; then
    # Add to metadata
    add_worktree_metadata "$name" "$branch" "$worktree_path"

    success "Worktree '${name}' created successfully!"
    info "Branch: ${branch}"
    info "Path: ${abs_path}"
    info ""
    info "To assign files to this worktree, use:"
    info "  wt assign <file> ${name}"
  else
    error "Failed to create worktree"
  fi
}
