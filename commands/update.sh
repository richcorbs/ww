#!/usr/bin/env bash
# Update ww-working with main

show_help() {
  cat <<EOF
Usage: ww update [branch]

Update ww-working with changes from another branch (default: main).
Merges the specified branch into ww-working to keep it up-to-date.
Automatically detects and cleans up worktrees whose branches have been merged.

Arguments:
  branch    Branch to update from (default: main)

Options:
  -h, --help    Show this help message

What it does:
  1. Fetches latest changes from origin
  2. Updates local branch from origin
  3. Merges branch into ww-working
  4. Detects worktrees with merged branches
  5. Removes merged worktrees automatically
  6. Deletes corresponding remote branches

Examples:
  ww update           # Update from main and clean up merged worktrees
  ww update develop   # Update from develop branch
EOF
}

cmd_update() {
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

  # Ensure on ww-working
  local current_branch
  current_branch=$(git branch --show-current)
  if [[ "$current_branch" != "ww-working" ]]; then
    warn "Not on ww-working branch, checking it out..."
    git checkout ww-working
  fi

  # Check if source branch exists
  if ! git show-ref --verify --quiet "refs/heads/${source_branch}"; then
    error "Branch '${source_branch}' does not exist"
  fi

  info "Updating ww-working with '${source_branch}'..."

  # Fetch latest changes
  if git remote get-url origin > /dev/null 2>&1; then
    info "Fetching latest changes from origin..."
    git fetch origin >/dev/null 2>&1 || warn "Failed to fetch from origin"

    # Update local source branch from origin
    info "Updating local ${source_branch} from origin/${source_branch}..."
    git fetch origin "${source_branch}:${source_branch}" >/dev/null 2>&1 || warn "Failed to update local ${source_branch}"
  fi

  # Merge source branch into ww-working
  if git merge --no-edit "${source_branch}" >/dev/null 2>&1; then
    success "Successfully updated ww-working with '${source_branch}'"

    # Show summary
    local merge_commit
    merge_commit=$(git rev-parse --short HEAD)
    info "Merge commit: ${merge_commit}"

    # Check for merged worktrees and clean them up
    info "Checking for merged branches..."
    echo ""

    # First, prune any stale worktree registrations
    git worktree prune 2>/dev/null

    local names
    names=$(list_worktree_names)
    local cleaned_count=0

    if [[ -n "$names" ]]; then
      while IFS= read -r name; do
        local branch
        branch=$(get_worktree_branch "$name")

        # Check if branch is merged into source branch
        # Note: + prefix means checked out in a worktree, * means current branch
        if git branch --merged "${source_branch}" | grep -q "^[*+ ]*${branch}$"; then
          info "Branch '${branch}' has been merged into ${source_branch}"

          # Check for uncommitted changes
          local repo_root
          repo_root=$(get_repo_root)
          local worktree_path
          worktree_path=$(get_worktree_path "$name")
          local abs_path="${repo_root}/${worktree_path}"

          local uncommitted_count
          uncommitted_count=$(get_worktree_uncommitted_count "$abs_path")

          if [[ "$uncommitted_count" -gt 0 ]]; then
            # Has uncommitted changes - recreate branch from updated ww-working
            info "  Worktree '${name}' has ${uncommitted_count} uncommitted change(s)"
            info "  Recreating branch '${branch}' from updated ww-working..."

            # Delete old branch
            git branch -D "${branch}" >/dev/null 2>&1

            # Create new branch from ww-working in the worktree
            if pushd "$abs_path" > /dev/null 2>&1; then
              git checkout -b "${branch}" ww-working >/dev/null 2>&1
              popd > /dev/null 2>&1
            fi

            # Delete remote branch if it exists
            if git ls-remote --exit-code --heads origin "${branch}" >/dev/null 2>&1; then
              info "  Deleting remote branch '${branch}'..."
              git push origin --delete "${branch}" >/dev/null 2>&1 || warn "  Failed to delete remote branch"
            fi

            success "  Recreated '${name}' with latest code, uncommitted changes preserved"
            echo ""
          else
            # No uncommitted changes - clean up completely
            info "  Removing worktree '${name}'..."

            # Try to remove worktree (may fail if already gone)
            git worktree remove ".worktrees/${name}" --force 2>/dev/null || true

            # Delete local branch (do this even if worktree removal failed)
            info "  Deleting local branch '${branch}'..."
            if git branch -d "${branch}" >/dev/null 2>&1 || git branch -D "${branch}" >/dev/null 2>&1; then
              # Delete remote branch if it exists
              if git ls-remote --exit-code --heads origin "${branch}" >/dev/null 2>&1; then
                info "  Deleting remote branch '${branch}'..."
                git push origin --delete "${branch}" 2>/dev/null || warn "  Failed to delete remote branch"
              fi

              success "  Cleaned up '${name}'"
              cleaned_count=$((cleaned_count + 1))
            else
              warn "  Failed to delete branch '${branch}' - it may have unmerged commits"
            fi
          fi
          echo ""
        fi
      done <<< "$names"
    fi

    if [[ $cleaned_count -gt 0 ]]; then
      success "Cleaned up ${cleaned_count} merged worktree(s)"
    else
      info "No merged worktrees to clean up"
    fi
    echo ""
    source "${WW_ROOT}/commands/status.sh"
    cmd_status
    exit 0
  else
    error "Merge conflicts detected. Please resolve them and commit."
  fi
}
