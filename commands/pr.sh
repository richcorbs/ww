#!/usr/bin/env bash
# Open GitHub PR creation page for a worktree

show_help() {
  cat <<EOF
Usage: ww pr [worktree]

Open the GitHub PR creation page for a worktree's branch in your browser.
The worktree branch must be pushed to origin first.
If worktree is not provided, fzf will show a list of all worktrees.

Arguments:
  worktree    Name of the worktree (optional - will prompt with fzf)

Options:
  -h, --help    Show this help message

Examples:
  ww pr                # Select worktree interactively
  ww pr feature-auth   # Open PR for specific worktree
EOF
}

cmd_pr() {
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
  if ! worktree_exists "$worktree_name"; then
    error "Worktree '$worktree_name' not found"
  fi

  # Get worktree branch
  local branch
  branch=$(get_worktree_branch "$worktree_name")

  if [[ -z "$branch" ]]; then
    error "Could not determine branch for worktree '$worktree_name'"
  fi

  # Get remote URL
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null)

  if [[ -z "$remote_url" ]]; then
    error "No origin remote found. Please add a remote first."
  fi

  # Check if we need to push (branch doesn't exist on remote OR local is ahead)
  local repo_root
  repo_root=$(get_repo_root)
  local worktree_path
  worktree_path=$(get_worktree_path "$worktree_name")
  local abs_path="${repo_root}/${worktree_path}"

  local needs_push=false

  if ! git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    # Branch doesn't exist on remote
    needs_push=true
  else
    # Branch exists, check if local is ahead
    if pushd "$abs_path" > /dev/null 2>&1; then
      local ahead_count
      ahead_count=$(git rev-list --count "origin/${branch}..HEAD" 2>/dev/null || echo "0")
      if [[ "$ahead_count" -gt 0 ]]; then
        needs_push=true
      fi
      popd > /dev/null 2>&1
    fi
  fi

  if [[ "$needs_push" == "true" ]]; then
    info "Pushing latest changes to origin..."

    if pushd "$abs_path" > /dev/null 2>&1; then
      if git push -u origin "$branch" 2>&1; then
        success "Pushed branch '${branch}' to origin"
      else
        popd > /dev/null 2>&1
        error "Failed to push branch '${branch}' to origin"
      fi
      popd > /dev/null 2>&1
    else
      error "Could not access worktree at: ${abs_path}"
    fi
  fi

  # Parse GitHub URL
  # Handle both HTTPS and SSH formats
  local github_url=""

  if [[ "$remote_url" =~ ^https://github.com/ ]]; then
    # HTTPS format: https://github.com/user/repo.git
    github_url=$(echo "$remote_url" | sed 's/\.git$//')
  elif [[ "$remote_url" =~ ^git@github.com: ]]; then
    # SSH format: git@github.com:user/repo.git
    github_url=$(echo "$remote_url" | sed 's/^git@github.com:/https:\/\/github.com\//' | sed 's/\.git$//')
  else
    error "Could not parse GitHub URL from remote: $remote_url"
  fi

  # Construct PR creation URL
  # Format: https://github.com/user/repo/compare/main...branch?expand=1
  local pr_url="${github_url}/compare/main...${branch}?expand=1"

  info "Opening PR creation page for branch '${branch}'..."
  info "URL: ${pr_url}"

  # Open in browser (cross-platform)
  if command -v open > /dev/null 2>&1; then
    # macOS
    open "$pr_url"
  elif command -v xdg-open > /dev/null 2>&1; then
    # Linux
    xdg-open "$pr_url"
  elif command -v start > /dev/null 2>&1; then
    # Windows
    start "$pr_url"
  else
    warn "Could not open browser automatically"
    info "Please open this URL manually: ${pr_url}"
  fi

  success "PR page opened for '${worktree_name}'"
  echo ""
  source "${WW_ROOT}/commands/status.sh"
  cmd_status
}
