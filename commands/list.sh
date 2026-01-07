#!/usr/bin/env bash
# List all worktrees

show_help() {
  cat <<EOF
Usage: wt list

List all worktrees with their branch information and status.

Options:
  -h, --help    Show this help message
EOF
}

cmd_list() {
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

  # Ensure initialized
  ensure_git_repo
  ensure_initialized

  local repo_root
  repo_root=$(get_repo_root)

  # Get all worktree names
  local names
  names=$(list_worktree_names)

  if [[ -z "$names" ]]; then
    info "No worktrees created yet"
    info "Use 'wt create <name> <branch>' to create one"
    exit 0
  fi

  echo "Worktrees:"
  echo ""

  while IFS= read -r name; do
    local branch
    branch=$(get_worktree_branch "$name")

    local path
    path=$(get_worktree_path "$name")

    local abs_path="${repo_root}/${path}"

    # Check if directory exists
    if [[ ! -d "$abs_path" ]]; then
      echo -e "  ${RED}${name}${NC} (${branch}) - ${RED}MISSING${NC}"
      echo "    Path: ${abs_path}"
      continue
    fi

    # Get commit count info
    local ahead_behind=""
    if pushd "$abs_path" > /dev/null 2>&1; then
      local current_branch
      current_branch=$(git branch --show-current 2>/dev/null || echo "")

      if [[ -n "$current_branch" ]]; then
        # Try to get ahead/behind info compared to origin
        local upstream
        upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "")

        if [[ -n "$upstream" ]]; then
          local ahead
          ahead=$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo "0")
          local behind
          behind=$(git rev-list --count "HEAD..${upstream}" 2>/dev/null || echo "0")

          if [[ "$ahead" -gt 0 ]] || [[ "$behind" -gt 0 ]]; then
            ahead_behind=" (↑${ahead} ↓${behind})"
          fi
        fi
      fi

      popd > /dev/null 2>&1
    fi

    # Count uncommitted changes
    local uncommitted_count=0
    if pushd "$abs_path" > /dev/null 2>&1; then
      uncommitted_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
      popd > /dev/null 2>&1
    fi

    local status_info=""
    if [[ "$uncommitted_count" -gt 0 ]]; then
      status_info=" - ${uncommitted_count} uncommitted change(s)"
    fi

    echo -e "  ${GREEN}${name}${NC} (${branch})${ahead_behind}${status_info}"
    echo "    Path: ${abs_path}"

  done <<< "$names"
}
