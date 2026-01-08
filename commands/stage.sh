#!/usr/bin/env bash
# Stage files in a worktree

show_help() {
  cat <<EOF
Usage: wt stage <worktree> [file|directory|.]

Stage files in a worktree for commit. If no file specified, opens fzf for interactive selection.

Arguments:
  worktree            Name of the worktree
  file|directory|.    Optional: File path, directory, or . for all files

Options:
  -h, --help    Show this help message

Examples:
  wt stage feature-auth                      # Interactive fzf selection
  wt stage feature-auth app/models/user.rb   # Stage single file
  wt stage feature-auth app/models/          # Stage all files in directory
  wt stage feature-auth .                    # Stage all files
EOF
}

cmd_stage() {
  # Parse arguments
  local worktree_name=""
  local file_or_pattern=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        if [[ -z "$worktree_name" ]]; then
          worktree_name="$1"
        elif [[ -z "$file_or_pattern" ]]; then
          file_or_pattern="$1"
        else
          error "Too many arguments"
        fi
        ;;
    esac
    shift
  done

  # Validate arguments
  if [[ -z "$worktree_name" ]]; then
    error "Missing required argument: worktree"
  fi

  # Ensure initialized
  ensure_git_repo
  ensure_initialized

  # Check if worktree exists
  if ! worktree_exists "$worktree_name"; then
    error "Worktree '$worktree_name' not found"
  fi

  verify_worktree_exists "$worktree_name"

  local repo_root
  repo_root=$(get_repo_root)

  local worktree_path
  worktree_path=$(get_worktree_path "$worktree_name")

  local abs_worktree_path="${repo_root}/${worktree_path}"

  # Enter worktree and stage
  if pushd "$abs_worktree_path" > /dev/null 2>&1; then
    # If no file specified, use fzf to select files
    if [[ -z "$file_or_pattern" ]]; then
      if ! command -v fzf > /dev/null 2>&1; then
        popd > /dev/null 2>&1
        error "fzf is required for interactive selection. Specify files directly or install fzf."
      fi

      # Get uncommitted files
      local uncommitted_files
      uncommitted_files=$(git status --porcelain 2>/dev/null || true)

      if [[ -z "$uncommitted_files" ]]; then
        popd > /dev/null 2>&1
        warn "No changes to stage"
        exit 0
      fi

      # Build file list with git status indicators
      # Filter out fully-staged files (X != space, Y == space)
      local file_list="*  [All files]"$'\n'
      declare -A seen_dirs

      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local status_code="${line:0:2}"
        local filepath="${line:3}"

        # Skip fully-staged files (nothing unstaged to stage)
        # Git format: XY where X=staged, Y=unstaged
        local X="${status_code:0:1}"
        local Y="${status_code:1:1}"

        # If Y is space, file is fully staged - skip it
        if [[ "$Y" == " " ]]; then
          continue
        fi

        # Swap X and Y for display: unstaged (Y) then staged (X)
        # Display as: YX for left-to-right visual progression
        local display_status="${Y}${X}"

        # Clean up double spaces
        if [[ "$display_status" == "  " ]]; then
          display_status=" "
        fi

        file_list+="${display_status}  ${filepath}"$'\n'

        # Add parent directory if not already added
        local dir=$(dirname "$filepath")
        if [[ "$dir" != "." ]] && [[ -z "${seen_dirs[$dir]}" ]]; then
          seen_dirs[$dir]=1
          file_list+="DIR  ${dir}/"$'\n'
        fi
      done <<< "$uncommitted_files"

      info "Select files to stage (TAB to select, ENTER to confirm)..."

      local selected_files
      selected_files=$(echo "$file_list" | fzf --multi --height=40% --border --prompt="Select files to stage> " --bind=ctrl-j:down,ctrl-k:up,ctrl-d:half-page-down,ctrl-u:half-page-up | sed 's/^..  //')

      if [[ -z "$selected_files" ]]; then
        popd > /dev/null 2>&1
        warn "No files selected"
        exit 0
      fi

      # Check if "[All files]" was selected
      if echo "$selected_files" | grep -q "\[All files\]"; then
        if git add -A 2>&1; then
          local staged_count
          staged_count=$(git diff --cached --name-only | wc -l | tr -d ' ')
          popd > /dev/null 2>&1
          success "Staged all ${staged_count} file(s) in '${worktree_name}'"
          echo ""
          source "${WT_ROOT}/commands/status.sh"
          cmd_status
        else
          popd > /dev/null 2>&1
          error "Failed to stage files"
        fi
      else
        # Stage selected files and directories
        local staged_count=0
        while IFS= read -r file; do
          [[ -z "$file" ]] && continue

          # Check if it's a directory (ends with /)
          if [[ "$file" == */ ]]; then
            # Directory selected - stage all files in it
            if git add "${file%/}" 2>&1; then
              local dir_count
              dir_count=$(git diff --cached --name-only | grep "^${file}" | wc -l | tr -d ' ')
              staged_count=$((staged_count + dir_count))
            fi
          else
            # File selected
            if git add "$file" 2>&1; then
              staged_count=$((staged_count + 1))
            fi
          fi
        done <<< "$selected_files"

        popd > /dev/null 2>&1
        success "Staged ${staged_count} file(s) in '${worktree_name}'"
        echo ""
        source "${WT_ROOT}/commands/status.sh"
        cmd_status
      fi
      return
    fi

    if [[ "$file_or_pattern" == "*" ]] || [[ "$file_or_pattern" == "." ]]; then
      # Stage all files
      info "Staging all files in '${worktree_name}'..."
      if git add -A 2>&1; then
        local staged_count
        staged_count=$(git diff --cached --name-only | wc -l | tr -d ' ')
        popd > /dev/null 2>&1
        success "Staged ${staged_count} file(s) in '${worktree_name}'"
        echo ""
        source "${WT_ROOT}/commands/status.sh"
        cmd_status
      else
        popd > /dev/null 2>&1
        error "Failed to stage files"
      fi
    elif [[ -d "$file_or_pattern" ]]; then
      # Stage directory
      info "Staging files in ${file_or_pattern}..."
      if git add "$file_or_pattern" 2>&1; then
        local staged_count
        staged_count=$(git diff --cached --name-only | grep "^${file_or_pattern%/}/" | wc -l | tr -d ' ')
        popd > /dev/null 2>&1
        success "Staged ${staged_count} file(s) from ${file_or_pattern} in '${worktree_name}'"
        echo ""
        source "${WT_ROOT}/commands/status.sh"
        cmd_status
      else
        popd > /dev/null 2>&1
        error "Failed to stage directory"
      fi
    else
      # Stage single file
      if git add "$file_or_pattern" 2>&1; then
        popd > /dev/null 2>&1
        success "Staged '${file_or_pattern}' in '${worktree_name}'"
        echo ""
        source "${WT_ROOT}/commands/status.sh"
        cmd_status
      else
        popd > /dev/null 2>&1
        error "Failed to stage file"
      fi
    fi
  else
    error "Failed to enter worktree directory"
  fi
}
