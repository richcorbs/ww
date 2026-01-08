#!/usr/bin/env bash
# Unstage files in a worktree

show_help() {
  cat <<EOF
Usage: wt unstage <worktree> <file|abbreviation|.>

Unstage files in a worktree (equivalent to git reset in the worktree).
This removes files from the staging area but keeps the changes as uncommitted.

Arguments:
  worktree             Name of the worktree
  file|abbreviation|.  File path, two-letter abbreviation, or . for all staged files

Options:
  -h, --help    Show this help message

Examples:
  wt unstage feature-auth ab                # Single file by abbreviation
  wt unstage feature-auth app/models/user.rb # Single file by path
  wt unstage feature-auth .                 # All staged files
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

  if [[ -z "$file_or_abbrev" ]]; then
    error "Missing required argument: file or abbreviation"
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

  # Handle unstaging
  if [[ "$file_or_abbrev" == "." ]]; then
    # Unstage all files
    info "Unstaging all files in '${worktree_name}'..."

    if git reset HEAD 2>&1; then
      success "Unstaged all files in '${worktree_name}'"
    else
      popd > /dev/null 2>&1
      error "Failed to unstage files"
    fi
  else
    # Resolve file path
    local filepath=""
    if [[ ${#file_or_abbrev} -eq 2 ]]; then
      # Try as abbreviation first - get uncommitted files
      local uncommitted_files_array=()
      while IFS= read -r line; do
        [[ -n "$line" ]] && uncommitted_files_array+=("${line:3}")
      done < <(git status --porcelain 2>/dev/null)

      local temp_path
      temp_path=$(get_filepath_from_abbrev "$file_or_abbrev" "${uncommitted_files_array[@]}")

      if [[ -n "$temp_path" ]]; then
        filepath="$temp_path"
      else
        # Treat as file path
        filepath="$file_or_abbrev"
      fi
    else
      filepath="$file_or_abbrev"
    fi

    # Unstage the file
    if git reset HEAD -- "$filepath" 2>&1; then
      success "Unstaged '${filepath}' in '${worktree_name}'"
    else
      popd > /dev/null 2>&1
      error "Failed to unstage '${filepath}'"
    fi
  fi

  popd > /dev/null 2>&1
}
