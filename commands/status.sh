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
  echo "  Working in: ${current_branch}"
  echo ""

  # Check if worktree-staging is behind main (show first)
  if git remote get-url origin > /dev/null 2>&1; then
    # Determine main branch name
    local main_branch
    main_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

    # Check if origin/main exists
    if git show-ref --verify --quiet "refs/remotes/origin/${main_branch}"; then
      # Compare worktree-staging with origin/main
      local behind_count
      behind_count=$(git rev-list --count HEAD..origin/${main_branch} 2>/dev/null || echo "0")

      if [[ "$behind_count" -gt 0 ]]; then
        info "Run 'wt sync' to merge latest changes from ${main_branch}"
        echo ""
      fi
    fi
  fi

  # Check if on worktree-staging branch
  if [[ "$current_branch" != "worktree-staging" ]]; then
    warn "Not on worktree-staging branch (currently on: ${current_branch})"
    info "Use 'git checkout worktree-staging' to switch"
    echo ""
  fi

  # Get uncommitted changes
  local changed_files
  changed_files=$(git diff --name-only 2>/dev/null || true)
  local staged_files
  staged_files=$(git diff --cached --name-only 2>/dev/null || true)
  local untracked_files
  untracked_files=$(git ls-files --others --exclude-standard 2>/dev/null || true)

  # Combine all files (unique)
  local all_files
  all_files=$(echo -e "${changed_files}\n${staged_files}\n${untracked_files}" | sort -u | grep -v '^$' || true)

  # Generate abbreviations for all files
  if [[ -n "$all_files" ]]; then
    local files_array=()
    while IFS= read -r file; do
      files_array+=("$file")
    done <<< "$all_files"

    generate_abbreviations_for_files "${files_array[@]}"
  fi

  # Display unassigned changes
  echo "  Unassigned changes:"
  if [[ -z "$all_files" ]]; then
    echo "    (none)"
  else
    # Pre-build associative arrays for file status (O(n) instead of O(n²))
    declare -A file_status_map
    while IFS= read -r file; do
      [[ -n "$file" ]] && file_status_map["$file"]="??"
    done <<< "$untracked_files"
    while IFS= read -r file; do
      [[ -n "$file" ]] && file_status_map["$file"]="A "
    done <<< "$staged_files"
    while IFS= read -r file; do
      [[ -n "$file" ]] && file_status_map["$file"]="M "
    done <<< "$changed_files"

    while IFS= read -r file; do
      local abbrev
      abbrev=$(get_abbreviation "$file")
      local status="${file_status_map[$file]}"
      echo -e "    ${YELLOW}${abbrev}${NC}  ${status} ${file}"
    done <<< "$all_files"
  fi

  echo ""

  # Display worktrees
  local names
  names=$(list_worktree_names)

  if [[ -z "$names" ]]; then
    echo "  Worktrees:"
    echo "    (none)"
    echo ""
    echo "    Use 'wt create <name> <branch>' to create a worktree"
  else
    echo "  Worktrees:"

    local repo_root
    repo_root=$(get_repo_root)

    while IFS= read -r name; do
      local branch
      branch=$(get_worktree_branch "$name")

      local path
      path=$(get_worktree_path "$name")

      local abs_path="${repo_root}/${path}"

      # Check if directory exists
      if [[ ! -d "$abs_path" ]]; then
        echo -e "    ${RED}${name}${NC} (${branch}) - ${RED}MISSING${NC}"
        continue
      fi

      # Get uncommitted files in worktree
      local uncommitted_files=()
      local uncommitted_count=0
      if pushd "$abs_path" > /dev/null 2>&1; then
        uncommitted_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

        # Get list of uncommitted files with status
        if [[ "$uncommitted_count" -gt 0 ]]; then
          while IFS= read -r line; do
            uncommitted_files+=("$line")
          done < <(git status --porcelain 2>/dev/null)
        fi

        popd > /dev/null 2>&1
      fi

      # Count commits not in worktree-staging
      local commit_count=0
      if pushd "$abs_path" > /dev/null 2>&1; then
        commit_count=$(git rev-list --count "worktree-staging..HEAD" 2>/dev/null || echo "0")
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
        status_str=" - $(IFS=", "; echo "${status_parts[*]}")"
      fi

      # Check if branch has been merged into main (check remote first, then local)
      local is_merged=false
      local main_branch="main"
      local check_branch=""

      # Prefer checking against origin/main if it exists
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
            pr_info=" ${GREEN}✓ Merged${NC} ${BLUE}PR #${pr_number}${NC}: ${pr_url}"
          else
            pr_info=" ${GREEN}✓ Merged into ${main_branch}${NC}"
          fi
        else
          # Query for open PR associated with this branch
          local pr_url
          pr_url=$(gh pr list --head "$branch" --json url --jq '.[0].url' 2>/dev/null || echo "")

          if [[ -n "$pr_url" ]]; then
            # Get PR number from URL
            local pr_number
            pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
            pr_info=" ${BLUE}PR #${pr_number}${NC}: ${pr_url}"
          fi
        fi
      elif [[ "$is_merged" == "true" ]]; then
        # No gh CLI, just show merged status
        pr_info=" ${GREEN}✓ Merged into ${main_branch}${NC}"
      fi

      echo -e "    ${GREEN}${name}${NC} (${branch})${status_str}"
      if [[ -n "$pr_info" ]]; then
        echo -e "      ${pr_info}"
      fi

      # Show uncommitted files if any
      if [[ ${#uncommitted_files[@]} -gt 0 ]]; then
        # Generate display-only abbreviations for worktree files (sequential to avoid conflicts)
        declare -A temp_abbrevs
        declare -A used_abbrevs  # Use associative array for O(1) lookups

        # Get current unassigned file abbreviations to avoid conflicts
        declare -A unassigned_abbrevs_map
        local unassigned_abbrevs_list
        unassigned_abbrevs_list=$(read_abbreviations 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
        while IFS= read -r abbrev; do
          [[ -n "$abbrev" ]] && unassigned_abbrevs_map["$abbrev"]=1
        done <<< "$unassigned_abbrevs_list"

        for file_status in "${uncommitted_files[@]}"; do
          local filepath="${file_status:3}"

          # Generate abbreviation based on filepath
          local abbrev
          abbrev=$(hash_filepath "$filepath")
          abbrev=$(hash_to_letters "$abbrev")

          # Check for collisions and find next available (O(1) lookups)
          while [[ -n "${used_abbrevs[$abbrev]:-}" ]] || [[ -n "${unassigned_abbrevs_map[$abbrev]:-}" ]]; do
            abbrev=$(find_next_abbrev "$abbrev")
          done

          temp_abbrevs["$filepath"]="$abbrev"
          used_abbrevs["$abbrev"]=1
        done

        # Display with abbreviations
        for file_status in "${uncommitted_files[@]}"; do
          local status_code="${file_status:0:2}"
          local filepath="${file_status:3}"
          local abbrev="${temp_abbrevs[$filepath]}"
          echo -e "      ${YELLOW}${abbrev}${NC}  ${status_code} ${filepath}"
        done
      fi

    done <<< "$names"
  fi

  echo ""
}
