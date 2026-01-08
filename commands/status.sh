#!/usr/bin/env bash
# Show uncommitted changes and worktree status

show_help() {
  cat <<EOF
Usage: wt status

Show uncommitted changes in staging with two-letter abbreviations,
and display all worktrees with their status.

Options:
  -h, --help    Show this help message
EOF
}

cmd_status() {
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

  # Auto-initialize if not already done
  if ! is_initialized; then
    warn "Worktree workflow not initialized. Initializing now..."
    cmd_init() { source "${WT_ROOT}/commands/init.sh" && cmd_init; }
    cmd_init
    echo ""
  fi

  # Fetch latest from origin to ensure status is up-to-date
  if git remote get-url origin > /dev/null 2>&1; then
    git fetch origin > /dev/null 2>&1 || true
  fi

  # Show current branch at the top
  local current_branch
  current_branch=$(git branch --show-current)

  # Check if wt-working is behind main
  local behind_status=""
  if [[ "$current_branch" == "wt-working" ]] && git remote get-url origin > /dev/null 2>&1; then
    # Determine main branch name
    local main_branch
    main_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

    # Check if origin/main exists
    if git show-ref --verify --quiet "refs/remotes/origin/${main_branch}"; then
      # Compare wt-working with origin/main
      local behind_count
      behind_count=$(git rev-list --count HEAD..origin/${main_branch} 2>/dev/null || echo "0")

      if [[ "$behind_count" -gt 0 ]]; then
        behind_status=" ${YELLOW}(${behind_count} behind origin/${main_branch})${NC}"
      fi
    fi
  fi

  echo -e "  Working in: ${current_branch}${behind_status}"
  echo ""

  # Check if on wt-working branch
  if [[ "$current_branch" != "wt-working" ]]; then
    warn "Not on wt-working branch (currently on: ${current_branch})"
    info "Use 'git checkout wt-working' to switch"
    echo ""
  fi

  # Get uncommitted changes using git status --porcelain
  local status_output
  status_output=$(git status --porcelain 2>/dev/null || true)

  # Display unassigned changes
  echo "  Unassigned changes:"
  if [[ -z "$status_output" ]]; then
    echo "    (none)"
  else
    # Display files with swapped status format for visual progression
    # Git format: XY where X=staged, Y=unstaged
    # Display as: YX for left-to-right visual progression (unstaged → staged)
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local status_code="${line:0:2}"
      local filepath="${line:3}"

      # Swap X and Y for display: unstaged (Y) then staged (X)
      local X="${status_code:0:1}"
      local Y="${status_code:1:1}"
      local display_status="${Y}${X}"

      # Clean up double spaces
      if [[ "$display_status" == "  " ]]; then
        display_status=" "
      fi

      echo -e "    ${display_status}  ${filepath}"
    done <<< "$status_output"
  fi

  echo ""

  # Display worktrees
  local names
  names=$(list_worktree_names)

  if [[ -z "$names" ]]; then
    echo "  Worktrees:"
    echo "    (none)"
    echo ""
    info "  Use 'wt create <branch>' to create a worktree"
  else
    echo "  Worktrees:"

    local repo_root
    repo_root=$(get_repo_root)

    # Determine main branch once
    local main_branch="main"
    local check_branch=""
    if git show-ref --verify --quiet refs/remotes/origin/main; then
      check_branch="origin/main"
      main_branch="main"
    elif git show-ref --verify --quiet refs/remotes/origin/master; then
      check_branch="origin/master"
      main_branch="master"
    elif git show-ref --verify --quiet refs/heads/main; then
      check_branch="main"
      main_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
      check_branch="master"
      main_branch="master"
    fi

    while IFS= read -r name; do
      local branch
      branch=$(get_worktree_branch "$name")

      local path
      path=$(get_worktree_path "$name")

      local abs_path="${repo_root}/${path}"

      # Check if directory exists
      if [[ ! -d "$abs_path" ]]; then
        echo -e "    ${RED}${name}${NC} - ${RED}MISSING${NC}"
        continue
      fi

      # Get uncommitted files and commit count in one pushd
      local uncommitted_files=()
      local uncommitted_count=0
      local commit_count=0
      if pushd "$abs_path" > /dev/null 2>&1; then
        uncommitted_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

        # Get list of uncommitted files with status
        if [[ "$uncommitted_count" -gt 0 ]]; then
          while IFS= read -r line; do
            uncommitted_files+=("$line")
          done < <(git status --porcelain 2>/dev/null)
        fi

        # Count commits not in wt-working
        commit_count=$(git rev-list --count "wt-working..HEAD" 2>/dev/null || echo "0")

        popd > /dev/null 2>&1
      fi

      # Check if this worktree's changes are in wt-working
      # Look for assignment commits for this worktree in wt-working
      local applied_status=""
      local assignment_commits
      assignment_commits=$(git log wt-working --oneline --grep="wt: assign .* to ${name}" --max-count=50 2>/dev/null || echo "")

      if [[ -n "$assignment_commits" ]]; then
        # Found assignment commits - worktree is applied to staging
        applied_status=" ${GREEN}[applied]${NC}"
      elif [[ "$commit_count" -gt 0 ]]; then
        # No assignment commits but has commits - check if commits are in staging via patch-id
        local unapplied_count=0
        if pushd "$abs_path" > /dev/null 2>&1; then
          # Get patch-ids of commits in worktree but not in wt-working
          local worktree_patches
          worktree_patches=$(git log --format='%H' wt-working..HEAD 2>/dev/null | while read commit; do git show "$commit" | git patch-id --stable 2>/dev/null | awk '{print $1}'; done)

          if [[ -n "$worktree_patches" ]]; then
            # Check each patch to see if it exists in wt-working
            while IFS= read -r patch_id; do
              # Search wt-working for this patch-id
              if ! git log --format='%H' wt-working --max-count=100 2>/dev/null | while read staging_commit; do git show "$staging_commit" | git patch-id --stable 2>/dev/null | awk '{print $1}'; done | grep -q "^${patch_id}$"; then
                unapplied_count=$((unapplied_count + 1))
              fi
            done <<< "$worktree_patches"
          fi
          popd > /dev/null 2>&1
        fi

        if [[ "$unapplied_count" -eq 0 ]]; then
          applied_status=" ${GREEN}[applied]${NC}"
        else
          applied_status=" ${YELLOW}[not applied]${NC}"
        fi
      fi

      # Check if branch is pushed and ahead/behind remote (only if there are commits)
      local push_status=""
      if [[ "$commit_count" -gt 0 ]] && pushd "$abs_path" > /dev/null 2>&1; then
        local upstream
        upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "")

        if [[ -n "$upstream" ]]; then
          local ahead
          ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
          local behind
          behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")

          if [[ "$ahead" -gt 0 ]] && [[ "$behind" -gt 0 ]]; then
            push_status=" ${YELLOW}[${ahead} ahead, ${behind} behind]${NC}"
          elif [[ "$ahead" -gt 0 ]]; then
            push_status=" ${YELLOW}[${ahead} ahead]${NC}"
          elif [[ "$behind" -gt 0 ]]; then
            push_status=" ${YELLOW}[${behind} behind]${NC}"
          else
            push_status=" ${GREEN}[pushed]${NC}"
          fi
        else
          push_status=" ${YELLOW}[not pushed]${NC}"
        fi
        popd > /dev/null 2>&1
      fi

      local status_parts=()
      if [[ "$uncommitted_count" -gt 0 ]]; then
        status_parts+=("${uncommitted_count} uncommitted")
      fi
      if [[ "$commit_count" -gt 0 ]]; then
        status_parts+=("${commit_count} commit(s)")
      fi

      local status_str=""
      if [[ ${#status_parts[@]} -gt 0 ]]; then
        status_str=" - $(IFS=", "; echo "${status_parts[*]}")${applied_status}${push_status}"
      elif [[ -n "$push_status" ]] || [[ -n "$applied_status" ]]; then
        status_str="${applied_status}${push_status}"
      else
        status_str=" - ${YELLOW}EMPTY${NC}"
      fi

      # Check if branch has been merged into main
      local is_merged=false
      if [[ -n "$check_branch" ]] && git branch --merged "$check_branch" 2>/dev/null | grep -q "^[*+ ]*${branch}$"; then
        is_merged=true
      fi

      # Check for associated PR using GitHub CLI
      local pr_info=""
      if command -v gh > /dev/null 2>&1; then
        if [[ "$is_merged" == "true" ]]; then
          # Check for merged PR
          local pr_data
          pr_data=$(gh pr list --head "$branch" --state merged --json number,url --jq '.[0]' 2>/dev/null || echo "")

          if [[ -n "$pr_data" ]] && [[ "$pr_data" != "null" ]]; then
            local pr_number
            pr_number=$(echo "$pr_data" | jq -r '.number')
            local pr_url
            pr_url=$(echo "$pr_data" | jq -r '.url')
            pr_info="${GREEN}✓ Merged${NC} ${BLUE}PR #${pr_number}${NC}: ${pr_url}"
          else
            pr_info="${GREEN}✓ Merged into ${main_branch}${NC}"
          fi
        else
          # Query for open PR associated with this branch
          local pr_url
          pr_url=$(gh pr list --head "$branch" --json url --jq '.[0].url' 2>/dev/null || echo "")

          if [[ -n "$pr_url" ]]; then
            # Get PR number from URL
            local pr_number
            pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
            pr_info="${BLUE}PR #${pr_number}${NC}: ${pr_url}"
          fi
        fi
      elif [[ "$is_merged" == "true" ]]; then
        # No gh CLI, just show merged status
        pr_info="${GREEN}✓ Merged into ${main_branch}${NC}"
      fi

      echo -e "    ${GREEN}${name}${NC}${status_str}"
      if [[ -n "$pr_info" ]]; then
        echo -e "      ${pr_info}"
      fi

      # Show uncommitted files if any
      if [[ ${#uncommitted_files[@]} -gt 0 ]]; then
        for file_status in "${uncommitted_files[@]}"; do
          local status_code="${file_status:0:2}"
          local filepath="${file_status:3}"

          # Swap X and Y for display: unstaged (Y) then staged (X)
          # Git format: XY where X=staged, Y=unstaged
          # Display as: YX for left-to-right visual progression
          local X="${status_code:0:1}"
          local Y="${status_code:1:1}"
          local display_status="${Y}${X}"

          # Clean up double spaces
          if [[ "$display_status" == "  " ]]; then
            display_status=" "
          fi

          echo -e "      ${display_status}  ${filepath}"
        done
      fi

    done <<< "$names"
  fi

  echo ""
}
