#!/usr/bin/env bash
# Assign a file to a worktree

show_help() {
  cat <<EOF
Usage: wt assign <file|abbreviation|directory|*> <worktree>

Assign uncommitted changes to a worktree and commit them to worktree-staging.
Can assign a single file, all files in a directory, all files, or use two-letter abbreviation.

Arguments:
  file|abbreviation|directory|*  File path, directory path, two-letter abbreviation, or * for all
  worktree                       Name of the worktree

Options:
  -h, --help    Show this help message

Examples:
  wt assign ab feature-auth                # Single file by abbreviation
  wt assign app/models/user.rb feature-auth # Single file by path
  wt assign app/models/ feature-auth       # All changed files in directory
  wt assign * feature-auth                 # All uncommitted files
EOF
}

cmd_assign() {
  # Parse arguments
  local file_or_abbrev=""
  local worktree_name=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        if [[ -z "$file_or_abbrev" ]]; then
          file_or_abbrev="$1"
        elif [[ -z "$worktree_name" ]]; then
          worktree_name="$1"
        else
          error "Too many arguments"
        fi
        ;;
    esac
    shift
  done

  # Validate arguments
  if [[ -z "$file_or_abbrev" ]]; then
    error "Missing required argument: file or abbreviation"
  fi

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

  # Resolve file path(s)
  local files_to_assign=()

  if [[ "$file_or_abbrev" == "*" ]]; then
    # Assign all uncommitted files
    info "Assigning all uncommitted changes..."

    # Get all changed files
    local changed_files
    changed_files=$(git diff --name-only 2>/dev/null || true)
    local staged_files
    staged_files=$(git diff --cached --name-only 2>/dev/null || true)
    local untracked_files
    untracked_files=$(git ls-files --others --exclude-standard 2>/dev/null || true)

    # Combine and deduplicate
    local all_files
    all_files=$(echo -e "${changed_files}\n${staged_files}\n${untracked_files}" | sort -u | grep -v '^$' || true)

    if [[ -z "$all_files" ]]; then
      warn "No uncommitted changes to assign"
      exit 0
    fi

    while IFS= read -r file; do
      files_to_assign+=("$file")
    done <<< "$all_files"

    info "Found ${#files_to_assign[@]} file(s) to assign"
  elif [[ ${#file_or_abbrev} -eq 2 ]]; then
    # Might be an abbreviation
    local filepath
    filepath=$(get_filepath_from_abbrev "$file_or_abbrev")

    if [[ -z "$filepath" ]]; then
      # Not found as abbreviation, treat as file path
      filepath="$file_or_abbrev"
    fi

    if [[ -d "$filepath" ]]; then
      # It's a directory
      :  # Will handle below
    else
      files_to_assign+=("$filepath")
    fi
  elif [[ -d "$file_or_abbrev" ]]; then
    # It's a directory - find all changed files in it
    local dir="${file_or_abbrev%/}"  # Remove trailing slash
    info "Finding changed files in ${dir}/"

    # Get all changed files in directory
    local changed_files
    changed_files=$(git diff --name-only | grep "^${dir}/" || true)
    local staged_files
    staged_files=$(git diff --cached --name-only | grep "^${dir}/" || true)
    local untracked_files
    untracked_files=$(git ls-files --others --exclude-standard | grep "^${dir}/" || true)

    # Combine and deduplicate
    local all_files
    all_files=$(echo -e "${changed_files}\n${staged_files}\n${untracked_files}" | sort -u | grep -v '^$' || true)

    if [[ -z "$all_files" ]]; then
      warn "No changed files found in ${dir}/"
      exit 0
    fi

    while IFS= read -r file; do
      files_to_assign+=("$file")
    done <<< "$all_files"

    info "Found ${#files_to_assign[@]} changed file(s) in ${dir}/"
  else
    # Single file
    files_to_assign+=("$file_or_abbrev")
  fi

  # Verify files exist and have changes
  for filepath in "${files_to_assign[@]}"; do
    if [[ ! -f "$filepath" ]] && ! git ls-files --error-unmatch "$filepath" > /dev/null 2>&1; then
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

    # Stage and commit the file to worktree-staging
    git add "$filepath"
    if git commit -m "wt: assign ${filepath} to ${worktree_name}"; then
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
        # Apply the patch
        if git apply "$patch_file" 2>/dev/null || cp "${repo_root}/${filepath}" "$filepath" 2>/dev/null; then
          ((assigned_count++))
        else
          popd > /dev/null 2>&1 || true
          rm -f "$patch_file"
          warn "Failed to apply ${filepath} to worktree, but it's committed to staging"
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
    success "Assigned ${assigned_count} file(s) to '${worktree_name}' and committed to worktree-staging"
    exit 0
  elif [[ $assigned_count -gt 0 ]]; then
    warn "Assigned ${assigned_count} of ${#files_to_assign[@]} file(s) to '${worktree_name}'"
    exit 0
  else
    error "Failed to assign files"
  fi
}
