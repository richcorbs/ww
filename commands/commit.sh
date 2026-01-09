#!/usr/bin/env bash
# Commit changes in a worktree

show_help() {
  cat <<EOF
Usage: ww commit [worktree] [message]

Commit changes in a worktree using interactive file selection.
Always opens fzf to select files to commit. Staged files are marked with [S].
If worktree is not provided, fzf will show a list of all worktrees.

Arguments:
  worktree    Name of the worktree (optional - will prompt with fzf)
  message     Optional commit message (pre-fills prompt if provided)

Options:
  -h, --help    Show this help message

Examples:
  ww commit                                          # Select worktree, then files, then message
  ww commit feature-auth "Add user authentication"  # Selects files, pre-fills message
  ww commit feature-auth                             # Selects files, prompts for message
EOF
}

cmd_commit() {
  # Parse arguments
  local worktree_name=""
  local commit_message=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        if [[ -z "$worktree_name" ]]; then
          worktree_name="$1"
        elif [[ -z "$commit_message" ]]; then
          commit_message="$1"
        else
          # Allow multi-word commit messages
          commit_message="${commit_message} $1"
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

  verify_worktree_exists "$worktree_name"

  local repo_root
  repo_root=$(get_repo_root)

  local worktree_path
  worktree_path=$(get_worktree_path "$worktree_name")

  local abs_worktree_path="${repo_root}/${worktree_path}"

  # Enter worktree directory
  if pushd "$abs_worktree_path" > /dev/null 2>&1; then
    # Check for uncommitted changes
    local uncommitted_count
    uncommitted_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$uncommitted_count" -eq 0 ]]; then
      popd > /dev/null 2>&1
      warn "No changes to commit in '${worktree_name}'"
      exit 0
    fi

    # Always use fzf for file selection
    if ! command -v fzf > /dev/null 2>&1; then
      popd > /dev/null 2>&1
      error "fzf is required for interactive file selection. Install fzf to use ww commit."
    fi

    # Get uncommitted files
    local uncommitted_files
    uncommitted_files=$(git status --porcelain 2>/dev/null || true)

    if [[ -z "$uncommitted_files" ]]; then
      popd > /dev/null 2>&1
      warn "No changes to commit"
      exit 0
    fi

    # Build file list with git status indicators
    local file_list="*  [All files]"$'\n'

    # Extract all file paths for directory extraction
    local all_file_paths=""
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local filepath="${line:3}"
      all_file_paths+="${filepath}"$'\n'
    done <<< "$uncommitted_files"

    # Extract directories using shared function
    local unique_dirs
    unique_dirs=$(extract_directories "$all_file_paths")

    # Add directories first
    while IFS= read -r dir; do
      [[ -n "$dir" ]] && file_list+="D   ${dir}/"$'\n'
    done <<< "$unique_dirs"

    # Add individual files with status
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local status_code="${line:0:2}"
      local filepath="${line:3}"

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

      # Add [S] indicator if file is staged (X != space)
      local staged_indicator=""
      if [[ "$X" != " " ]]; then
        staged_indicator=" [S]"
      fi

      file_list+="${display_status}  ${filepath}${staged_indicator}"$'\n'
    done <<< "$uncommitted_files"

    info "Select files to commit (TAB to select, ENTER to confirm)..."

    local selected_files
    selected_files=$(echo "$file_list" | run_fzf "Search files: " | sed 's/^..  //' | sed 's/ \[S\]$//')

    if [[ -z "$selected_files" ]]; then
      popd > /dev/null 2>&1
      warn "No files selected"
      exit 0
    fi

    # Check if "[All files]" was selected
    if echo "$selected_files" | grep -q "\[All files\]"; then
      info "Staging all files..."
      git add -A 2>&1
    else
      # Expand directories using shared function
      local expanded_files
      expanded_files=$(expand_directory_selections "$selected_files" "$all_file_paths")

      # Stage selected files
      info "Staging selected files..."
      while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        git add "$file" 2>&1
      done <<< "$expanded_files"
    fi

    # Prompt for commit message (with pre-fill if provided)
    popd > /dev/null 2>&1
    echo ""

    local final_message
    if [[ -n "$commit_message" ]]; then
      # Message provided - use it as default but allow editing
      read -p "Commit message: " -i "$commit_message" -e final_message
      # If user cleared it, use original
      if [[ -z "$final_message" ]]; then
        final_message="$commit_message"
      fi
    else
      # No message provided - prompt for one
      read -p "Commit message: " final_message
    fi

    if [[ -z "$final_message" ]]; then
      error "Commit message cannot be empty"
    fi

    # Update commit_message for later use
    commit_message="$final_message"

    # Go back into worktree to commit
    if ! pushd "$abs_worktree_path" > /dev/null 2>&1; then
      error "Failed to re-enter worktree directory"
    fi

    if git commit -m "$commit_message" 2>&1; then
      local commit_sha
      commit_sha=$(git rev-parse HEAD)
      local short_sha
      short_sha=$(git rev-parse --short HEAD)

      popd > /dev/null 2>&1

      success "Changes committed in '${worktree_name}'"
      info "Commit: ${short_sha}"
      info "Message: ${commit_message}"
      echo ""
      source "${WW_ROOT}/commands/status.sh"
      cmd_status
    else
      popd > /dev/null 2>&1
      error "Failed to commit changes"
    fi
  else
    error "Failed to enter worktree directory"
  fi
}
