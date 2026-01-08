#!/usr/bin/env bash
# Assign files to a worktree

show_help() {
  cat <<EOF
Usage: wt assign <worktree> [file|directory|.]

Assign uncommitted changes to a worktree and commit them to wt-working.

Arguments:
  worktree            Name of the worktree
  file|directory|.    Optional: File path, directory, or . for all
                      If omitted, opens fzf for interactive selection

Options:
  -h, --help    Show this help message

Examples:
  wt assign feature-auth                      # Interactive fzf selection
  wt assign feature-auth app/models/user.rb   # Single file by path
  wt assign feature-auth app/models/          # All changed files in directory
  wt assign feature-auth .                    # All uncommitted files
EOF
}

cmd_assign() {
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

  # Check if worktree exists, create if it doesn't
  if ! worktree_exists "$worktree_name"; then
    info "Worktree '$worktree_name' doesn't exist, creating it..."

    local repo_root
    repo_root=$(get_repo_root)

    # Ensure we're on wt-working
    local current_branch
    current_branch=$(git branch --show-current)
    if [[ "$current_branch" != "${WT_BRANCH}" ]]; then
      git checkout ${WT_BRANCH} > /dev/null 2>&1
    fi

    # Path is always .worktrees/<branch>
    local worktree_path=".worktrees/${worktree_name}"
    local abs_path="${repo_root}/${worktree_path}"

    # Create the worktree from wt-working
    if git worktree add -b "$worktree_name" "$abs_path" ${WT_BRANCH} 2>&1; then
      success "Created worktree '$worktree_name'"
      echo ""
    else
      error "Failed to create worktree"
    fi
  fi

  # Get all uncommitted files
  local changed_files
  changed_files=$(git diff --name-only 2>/dev/null || true)
  local staged_files
  staged_files=$(git diff --cached --name-only 2>/dev/null || true)
  local untracked_files
  untracked_files=$(git ls-files --others --exclude-standard 2>/dev/null || true)

  local all_files
  all_files=$(echo -e "${changed_files}\n${staged_files}\n${untracked_files}" | sort -u | grep -v '^$' || true)

  if [[ -z "$all_files" ]]; then
    warn "No uncommitted changes to assign"
    exit 0
  fi

  # Resolve file path(s)
  local files_to_assign=()

  if [[ -z "$file_or_pattern" ]]; then
    # No file specified - use fzf for interactive selection
    if ! command -v fzf > /dev/null 2>&1; then
      error "fzf is required for interactive selection. Install fzf or specify files directly."
    fi

    # Extract directories using shared function
    local unique_dirs
    unique_dirs=$(extract_directories "$all_files")

    # Build file list with git status indicators
    local file_list="*  [All files]"$'\n'

    # Add directories first
    while IFS= read -r dir; do
      [[ -n "$dir" ]] && file_list+="D  ${dir}/"$'\n'
    done <<< "$unique_dirs"

    # Add individual files
    while IFS= read -r file; do
      local status="  "

      # Determine status
      if echo "$untracked_files" | grep -qx "$file"; then
        status="?"
      elif echo "$staged_files" | grep -qx "$file"; then
        status="A"
      elif echo "$changed_files" | grep -qx "$file"; then
        status="M"
      fi

      file_list+="${status}  ${file}"$'\n'
    done <<< "$all_files"

    info "Select files to assign (TAB to select, ENTER to confirm)..."

    local selected_files
    selected_files=$(echo "$file_list" | run_fzf "Select files for ${worktree_name}" | sed 's/^.  //')

    if [[ -z "$selected_files" ]]; then
      warn "No files selected"
      exit 0
    fi

    # Check if "[All files]" was selected
    if echo "$selected_files" | grep -q "\[All files\]"; then
      # Assign all files
      while IFS= read -r file; do
        files_to_assign+=("$file")
      done <<< "$all_files"
    else
      # Expand directories using shared function
      local expanded_files
      expanded_files=$(expand_directory_selections "$selected_files" "$all_files")

      while IFS= read -r file; do
        [[ -n "$file" ]] && files_to_assign+=("$file")
      done <<< "$expanded_files"
    fi

  elif [[ "$file_or_pattern" == "*" ]] || [[ "$file_or_pattern" == "." ]]; then
    # Assign all uncommitted files
    info "Assigning all uncommitted changes..."

    while IFS= read -r file; do
      files_to_assign+=("$file")
    done <<< "$all_files"

    info "Found ${#files_to_assign[@]} file(s) to assign"

  elif [[ -d "$file_or_pattern" ]]; then
    # It's a directory - find all changed files in it
    local dir="${file_or_pattern%/}"  # Remove trailing slash
    info "Finding changed files in ${dir}/"

    # Get all changed files in directory
    local dir_changed
    dir_changed=$(git diff --name-only | grep "^${dir}/" || true)
    local dir_staged
    dir_staged=$(git diff --cached --name-only | grep "^${dir}/" || true)
    local dir_untracked
    dir_untracked=$(git ls-files --others --exclude-standard | grep "^${dir}/" || true)

    # Combine and deduplicate
    local dir_files
    dir_files=$(echo -e "${dir_changed}\n${dir_staged}\n${dir_untracked}" | sort -u | grep -v '^$' || true)

    if [[ -z "$dir_files" ]]; then
      warn "No changed files found in ${dir}/"
      exit 0
    fi

    while IFS= read -r file; do
      files_to_assign+=("$file")
    done <<< "$dir_files"

    info "Found ${#files_to_assign[@]} changed file(s) in ${dir}/"
  else
    # Single file
    files_to_assign+=("$file_or_pattern")
  fi

  # Verify files exist or are deleted/changed in git
  for filepath in "${files_to_assign[@]}"; do
    # Check if file exists, or is tracked by git, or is in git status (including deletions)
    if [[ ! -f "$filepath" ]] && ! git ls-files --error-unmatch "$filepath" > /dev/null 2>&1 && ! git status --porcelain "$filepath" 2>/dev/null | grep -q '^.'; then
      error "File '$filepath' not found in repository"
    fi
  done

  # Get worktree path
  verify_worktree_exists "$worktree_name"

  local repo_root
  repo_root=$(get_repo_root)

  local worktree_path
  worktree_path=$(get_worktree_path "$worktree_name")

  local abs_worktree_path="${repo_root}/${worktree_path}"

  # Process each file
  local assigned_count=0

  for filepath in "${files_to_assign[@]}"; do
    info "Assigning ${filepath}..."

    # Stage the file (handles both regular files and deletions)
    if [[ -f "$filepath" ]]; then
      git add "$filepath"
    else
      # File is deleted - stage the deletion
      git add -u "$filepath" 2>/dev/null || git rm "$filepath" 2>/dev/null || true
    fi

    # Commit the file to wt-working
    if git commit -m "$(assignment_commit_message "$filepath" "$worktree_name")"; then
      local commit_sha
      commit_sha=$(git rev-parse HEAD)
      local short_sha
      short_sha=$(git rev-parse --short HEAD)

      # Create patch from the commit
      local patch_file
      patch_file=$(mktemp)
      git show "$commit_sha" -- "$filepath" > "$patch_file"

      # Apply to worktree
      if pushd "$abs_worktree_path" > /dev/null 2>&1; then
        # Apply the patch (handles both modifications and deletions)
        if git apply "$patch_file" 2>/dev/null; then
          assigned_count=$((assigned_count + 1))
        elif [[ -f "${repo_root}/${filepath}" ]]; then
          # Fallback: copy file if patch failed and file exists
          if cp "${repo_root}/${filepath}" "$filepath" 2>/dev/null; then
            assigned_count=$((assigned_count + 1))
          else
            popd > /dev/null 2>&1 || true
            rm -f "$patch_file"
            warn "Failed to apply ${filepath} to worktree, but it's committed to staging"
          fi
        else
          # File was deleted - git apply should have handled it, but count it anyway
          assigned_count=$((assigned_count + 1))
        fi

        popd > /dev/null 2>&1 || true
      else
        rm -f "$patch_file"
        warn "Failed to enter worktree directory for ${filepath}, but it's committed to staging"
      fi

      rm -f "$patch_file"
    else
      warn "Failed to commit ${filepath} to staging"
    fi
  done

  if [[ $assigned_count -eq ${#files_to_assign[@]} ]]; then
    success "Assigned ${assigned_count} file(s) to '${worktree_name}' and committed to wt-working"
    echo ""
    # Show updated status
    source "${WT_ROOT}/commands/status.sh"
    cmd_status
  elif [[ $assigned_count -gt 0 ]]; then
    warn "Assigned ${assigned_count} of ${#files_to_assign[@]} file(s) to '${worktree_name}'"
    echo ""
    # Show updated status
    source "${WT_ROOT}/commands/status.sh"
    cmd_status
  else
    error "Failed to assign files"
  fi
}
