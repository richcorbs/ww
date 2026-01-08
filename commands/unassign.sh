#!/usr/bin/env bash
# Unassign a file from a worktree

show_help() {
  cat <<EOF
Usage: wt unassign <worktree> [file|.]

Unassign file(s) from a worktree by reverting their commits in worktree-staging
and removing the changes from the worktree. The files will show up as
"unassigned" again.

Arguments:
  worktree     Name of the worktree
  file|.|      Optional: File path, directory, or . for all assigned files

Options:
  -h, --help    Show this help message

Examples:
  wt unassign feature-auth                    # Unassign all files
  wt unassign feature-auth app/models/user.rb # Single file by path
  wt unassign feature-auth .                  # All uncommitted files assigned to the worktree
EOF
}

cmd_unassign() {
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

  # Default to all files if no file specified
  if [[ -z "$file_or_abbrev" ]]; then
    file_or_abbrev="."
  fi

  # Ensure initialized
  ensure_git_repo
  ensure_initialized

  # Ensure on worktree-staging
  local current_branch
  current_branch=$(git branch --show-current)
  if [[ "$current_branch" != "worktree-staging" ]]; then
    error "Must be on worktree-staging branch to unassign. Current branch: ${current_branch}"
  fi

  # Check if worktree exists
  if ! worktree_exists "$worktree_name"; then
    error "Worktree '$worktree_name' not found"
  fi

  # Check if unassigning all files
  if [[ "$file_or_abbrev" == "." ]]; then
    info "Unassigning all files from '${worktree_name}'..."

    # Find all assignment commits for this worktree
    local commit_pattern="wt: assign .* to ${worktree_name}"
    local commits_to_revert=()

    while IFS= read -r sha; do
      local msg
      msg=$(git log -1 --format="%s" "$sha")

      if [[ "$msg" =~ ^wt:\ assign\ .*\ to\ ${worktree_name}$ ]]; then
        commits_to_revert+=("$sha")
      fi
    done < <(git log --format="%H" -n 100)  # Search last 100 commits

    if [[ ${#commits_to_revert[@]} -eq 0 ]]; then
      warn "No assignment commits found for '${worktree_name}'"
      exit 0
    fi

    info "Found ${#commits_to_revert[@]} assignment commit(s) to revert"

    # Revert commits in reverse order (newest first)
    for commit_sha in "${commits_to_revert[@]}"; do
      local short_sha
      short_sha=$(git rev-parse --short "$commit_sha")

      if ! git revert --no-edit "$commit_sha" 2>&1; then
        error "Failed to revert commit ${short_sha}. There may be conflicts."
      fi
    done

    success "Unassigned all files from '${worktree_name}'"
    info "Files are now uncommitted in worktree-staging"
    echo ""
    source "${WT_ROOT}/commands/status.sh"
    cmd_status
    exit 0
  fi

  # Find the commit that assigned this file to this worktree
  info "Searching for assignment commit..."

  local filepath="$file_or_abbrev"
  local commit_sha=""
  local commit_msg="wt: assign ${filepath} to ${worktree_name}"

  # Search recent commits for the assignment
  while IFS= read -r sha; do
    local msg
    msg=$(git log -1 --format="%s" "$sha")

    if [[ "$msg" == "$commit_msg" ]]; then
      commit_sha="$sha"
      break
    fi
  done < <(git log --format="%H" -n 50)  # Search last 50 commits

  if [[ -z "$commit_sha" ]]; then
    error "Could not find assignment commit for '${filepath}' to '${worktree_name}'"
  fi

  local short_sha
  short_sha=$(git rev-parse --short "$commit_sha")

  info "Found assignment commit: ${short_sha}"

  # Revert the commit
  info "Reverting commit..."

  if git revert --no-edit "$commit_sha" 2>&1; then
    success "Unassigned '${filepath}' from '${worktree_name}'"
    info "File is now uncommitted in worktree-staging"

    # Try to remove from worktree (best effort)
    local repo_root
    repo_root=$(get_repo_root)

    local worktree_path
    worktree_path=$(get_worktree_path "$worktree_name")

    local abs_worktree_path="${repo_root}/${worktree_path}"

    if [[ -d "$abs_worktree_path" ]]; then
      if pushd "$abs_worktree_path" > /dev/null 2>&1; then
        if [[ -f "$filepath" ]]; then
          git checkout HEAD -- "$filepath" 2>/dev/null || rm -f "$filepath"
          info "Removed changes from worktree"
        fi
        popd > /dev/null 2>&1
      fi
    fi
    echo ""
    source "${WT_ROOT}/commands/status.sh"
    cmd_status
  else
    error "Failed to revert commit. There may be conflicts."
  fi
}
