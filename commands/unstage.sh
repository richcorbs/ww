#!/usr/bin/env bash
# Unstage files in a worktree

show_help() {
  cat <<EOF
Usage: wt unstage <worktree> [file|.]

Unstage files in a worktree (equivalent to git reset in the worktree).
This removes files from the staging area but keeps the changes as uncommitted.
If no file specified, opens fzf for interactive selection.

Arguments:
  worktree     Name of the worktree
  file|.|      Optional: File path, directory, or . for all staged files

Options:
  -h, --help    Show this help message

Examples:
  wt unstage feature-auth                    # Interactive fzf selection
  wt unstage feature-auth app/models/user.rb # Single file by path
  wt unstage feature-auth .                  # All staged files
EOF
}

cmd_unstage() {
  # Parse arguments
  local worktree_name=""
  local file_or_abbrev=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        if [[ -z "$worktree_name" ]]; then
          worktree_name="$1"
        elif [[ -z "$file_or_abbrev" ]]; then
          file_or_abbrev="$1"
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

  # Get worktree path
  local repo_root
  repo_root=$(get_repo_root)

  local worktree_path
  worktree_path=$(get_worktree_path "$worktree_name")

  local abs_path="${repo_root}/${worktree_path}"

  if [[ ! -d "$abs_path" ]]; then
    error "Worktree directory not found: ${abs_path}"
  fi

  # Navigate to worktree
  if ! pushd "$abs_path" > /dev/null 2>&1; then
    error "Could not access worktree at: ${abs_path}"
  fi

  # If no file specified, use fzf to select files
  if [[ -z "$file_or_abbrev" ]]; then
    if ! command -v fzf > /dev/null 2>&1; then
      popd > /dev/null 2>&1
      error "fzf is required for interactive selection. Specify files directly or install fzf."
    fi

    # Get staged files (X != space in XY format)
    local staged_files
    staged_files=$(git status --porcelain 2>/dev/null | while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local status_code="${line:0:2}"
      local filepath="${line:3}"
      local X="${status_code:0:1}"

      # Only include files with something staged (X != space)
      if [[ "$X" != " " ]]; then
        echo "$line"
      fi
    done)

    if [[ -z "$staged_files" ]]; then
      popd > /dev/null 2>&1
      warn "No staged files to unstage"
      exit 0
    fi

    # Build file list with git status indicators
    local file_list="*  [All files]"$'\n'
    declare -A seen_dirs

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

      file_list+="${display_status}  ${filepath}"$'\n'

      # Add parent directory if not already added
      local dir=$(dirname "$filepath")
      if [[ "$dir" != "." ]] && [[ -z "${seen_dirs[$dir]}" ]]; then
        seen_dirs[$dir]=1
        file_list+="DIR  ${dir}/"$'\n'
      fi
    done <<< "$staged_files"

    info "Select files to unstage (TAB to select, ENTER to confirm)..."

    local selected_files
    selected_files=$(echo "$file_list" | fzf --multi --height=40% --border --prompt="Select files to unstage> " --bind=ctrl-j:down,ctrl-k:up,ctrl-d:half-page-down,ctrl-u:half-page-up | sed 's/^..  //')

    if [[ -z "$selected_files" ]]; then
      popd > /dev/null 2>&1
      warn "No files selected"
      exit 0
    fi

    # Check if "[All files]" was selected
    if echo "$selected_files" | grep -q "\[All files\]"; then
      if git reset HEAD 2>&1; then
        popd > /dev/null 2>&1
        success "Unstaged all files in '${worktree_name}'"
        echo ""
        source "${WT_ROOT}/commands/status.sh"
        cmd_status
      else
        popd > /dev/null 2>&1
        error "Failed to unstage files"
      fi
    else
      # Unstage selected files and directories
      local unstaged_count=0
      while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Check if it's a directory (ends with /)
        if [[ "$file" == */ ]]; then
          # Directory selected - unstage all files in it
          if git reset HEAD -- "${file%/}" 2>&1; then
            local dir_count
            dir_count=$(git diff --name-only | grep "^${file}" | wc -l | tr -d ' ')
            unstaged_count=$((unstaged_count + dir_count))
          fi
        else
          # File selected
          if git reset HEAD -- "$file" 2>&1; then
            unstaged_count=$((unstaged_count + 1))
          fi
        fi
      done <<< "$selected_files"

      popd > /dev/null 2>&1
      success "Unstaged ${unstaged_count} file(s) in '${worktree_name}'"
      echo ""
      source "${WT_ROOT}/commands/status.sh"
      cmd_status
    fi
    return
  fi

  # Handle unstaging with file argument
  if [[ "$file_or_abbrev" == "." ]]; then
    # Unstage all files
    info "Unstaging all files in '${worktree_name}'..."

    if git reset HEAD 2>&1; then
      popd > /dev/null 2>&1
      success "Unstaged all files in '${worktree_name}'"
      echo ""
      source "${WT_ROOT}/commands/status.sh"
      cmd_status
    else
      popd > /dev/null 2>&1
      error "Failed to unstage files"
    fi
  else
    # Unstage the file
    if git reset HEAD -- "$file_or_abbrev" 2>&1; then
      popd > /dev/null 2>&1
      success "Unstaged '${file_or_abbrev}' in '${worktree_name}'"
      echo ""
      source "${WT_ROOT}/commands/status.sh"
      cmd_status
    else
      popd > /dev/null 2>&1
      error "Failed to unstage '${file_or_abbrev}'"
    fi
  fi
}
