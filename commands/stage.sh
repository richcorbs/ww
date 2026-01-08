#!/usr/bin/env bash
# Stage files in a worktree

show_help() {
  cat <<EOF
Usage: wt stage <worktree> <file|directory|*>

Stage files in a worktree for commit.

Arguments:
  worktree            Name of the worktree
  file|directory|*    File path, directory path, or * for all files

Options:
  -h, --help    Show this help message

Examples:
  wt stage feature-auth app/models/user.rb  # Stage single file
  wt stage feature-auth app/models/          # Stage all files in directory
  wt stage feature-auth *                    # Stage all files
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

  if [[ -z "$file_or_pattern" ]]; then
    error "Missing required argument: file|directory|*"
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
    # Resolve abbreviation if needed
    local resolved_file="$file_or_pattern"
    if [[ ${#file_or_pattern} -eq 2 ]] && [[ ! -f "$file_or_pattern" ]] && [[ ! -d "$file_or_pattern" ]]; then
      # Might be an abbreviation - get uncommitted files in this worktree
      local uncommitted_files_array=()
      while IFS= read -r line; do
        [[ -n "$line" ]] && uncommitted_files_array+=("${line:3}")
      done < <(git status --porcelain 2>/dev/null)

      if [[ ${#uncommitted_files_array[@]} -gt 0 ]]; then
        local temp_resolved
        temp_resolved=$(get_filepath_from_abbrev "$file_or_pattern" "${uncommitted_files_array[@]}")

        if [[ -n "$temp_resolved" ]]; then
          resolved_file="$temp_resolved"
          info "Resolved abbreviation '${file_or_pattern}' to '${resolved_file}'"
        fi
      fi
    fi

    if [[ "$resolved_file" == "*" ]] || [[ "$resolved_file" == "." ]]; then
      # Stage all files
      info "Staging all files in '${worktree_name}'..."
      if git add -A 2>&1; then
        local staged_count
        staged_count=$(git diff --cached --name-only | wc -l | tr -d ' ')
        popd > /dev/null 2>&1
        success "Staged ${staged_count} file(s) in '${worktree_name}'"
      else
        popd > /dev/null 2>&1
        error "Failed to stage files"
      fi
    elif [[ -d "$resolved_file" ]]; then
      # Stage directory
      info "Staging files in ${resolved_file}..."
      if git add "$resolved_file" 2>&1; then
        local staged_count
        staged_count=$(git diff --cached --name-only | grep "^${resolved_file%/}/" | wc -l | tr -d ' ')
        popd > /dev/null 2>&1
        success "Staged ${staged_count} file(s) from ${resolved_file} in '${worktree_name}'"
      else
        popd > /dev/null 2>&1
        error "Failed to stage directory"
      fi
    else
      # Stage single file
      if git add "$resolved_file" 2>&1; then
        popd > /dev/null 2>&1
        success "Staged '${resolved_file}' in '${worktree_name}'"
      else
        popd > /dev/null 2>&1
        error "Failed to stage file"
      fi
    fi
  else
    error "Failed to enter worktree directory"
  fi
}
