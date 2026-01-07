#!/usr/bin/env bash
# Unassign a file from a worktree

show_help() {
  cat <<EOF
Usage: wt unassign <file|abbreviation> <worktree>

Unassign a file from a worktree by reverting its commit in worktree-staging
and removing the changes from the worktree. The file will show up as
"unassigned" again.

Arguments:
  file|abbreviation  File path or two-letter abbreviation
  worktree           Name of the worktree

Options:
  -h, --help    Show this help message

Examples:
  wt unassign ab feature-auth
  wt unassign app/models/user.rb feature-auth
EOF
}

cmd_unassign() {
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

  # Resolve file path
  local filepath=""
  if [[ ${#file_or_abbrev} -eq 2 ]]; then
    # Try as abbreviation first (though it won't be in abbreviations if assigned)
    local temp_path
    temp_path=$(get_filepath_from_abbrev "$file_or_abbrev")

    if [[ -n "$temp_path" ]]; then
      filepath="$temp_path"
    else
      # Treat as file path
      filepath="$file_or_abbrev"
    fi
  else
    filepath="$file_or_abbrev"
  fi

  # Find the commit that assigned this file to this worktree
  info "Searching for assignment commit..."

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
  else
    error "Failed to revert commit. There may be conflicts."
  fi
}
