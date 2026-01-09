#!/usr/bin/env bash
# Shared library functions for worktree workflow scripts

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Constants
readonly WW_BRANCH="ww-working"
readonly FZF_OPTS="--multi --height=40% --border --bind=ctrl-j:down,ctrl-k:up,ctrl-d:half-page-down,ctrl-u:half-page-up"

# Generate assignment commit message
# Usage: assignment_commit_message "filepath" "worktree_name"
assignment_commit_message() {
  echo "ww: assign $1 to $2"
}

# Parse assignment commit to extract worktree name
# Usage: worktree_name=$(parse_assignment_commit "ww: assign file.txt to my-worktree")
parse_assignment_worktree() {
  local commit_msg="$1"
  echo "$commit_msg" | sed -n 's/^ww: assign .* to \(.*\)$/\1/p'
}

# Error handling
error() {
  echo -e "  ${RED}Error: $1${NC}" >&2
  exit 1
}

warn() {
  echo -e "  ${YELLOW}Warning: $1${NC}" >&2
}

info() {
  echo -e "  ${BLUE}$1${NC}"
}

success() {
  echo -e "  ${GREEN}$1${NC}"
}

# Git repository checks
ensure_git_repo() {
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not a git repository. Please run this command from within a git repository."
  fi
}

get_repo_root() {
  git rev-parse --show-toplevel
}

# Check if ww is initialized (ww-working branch exists)
is_initialized() {
  git show-ref --verify --quiet "refs/heads/${WW_BRANCH}"
}

ensure_initialized() {
  if ! is_initialized; then
    error "Worktree workflow not initialized. Run 'ww init' first."
  fi
}

# Get worktree path for a given branch name (returns relative path)
# The 'git worktree list --porcelain' command outputs structured data:
#   worktree /full/path/to/worktree
#   HEAD <sha>
#   branch refs/heads/branch-name
# This function parses that output to find the path for the specified branch
get_worktree_path() {
  local branch="$1"
  local repo_root
  repo_root=$(get_repo_root)

  # Parse git worktree list to find the path for this branch
  # Returns path relative to repo root
  git worktree list --porcelain | awk -v branch="$branch" -v root="$repo_root" '
    # Extract path from "worktree /path" line (skip first 10 chars: "worktree ")
    /^worktree / { path = substr($0, 10) }
    # When we find the branch line, check if it matches our target
    /^branch / {
      if ($2 == "refs/heads/" branch && path != root) {
        # Strip root prefix to get relative path
        # If path starts with "root/", remove that prefix (+2 for the slash and 0-based index)
        if (index(path, root "/") == 1) {
          print substr(path, length(root) + 2)
        } else {
          print path
        }
        exit
      }
    }
  '
}

# Check if worktree exists for a given branch name
worktree_exists() {
  local branch="$1"
  local path
  path=$(get_worktree_path "$branch")
  [[ -n "$path" ]]
}

# Get all worktree branch names (excluding main repo)
# Parses the porcelain output and extracts branch names for all worktrees
# except the main repository (identified by matching the repo root path)
list_worktree_names() {
  local repo_root
  repo_root=$(get_repo_root)

  git worktree list --porcelain | awk -v root="$repo_root" '
    # Extract path from "worktree /path" line
    /^worktree / { path = substr($0, 10) }
    # Extract branch name from "branch refs/heads/..." line
    /^branch / {
      # Skip the main repo (path == root)
      if (path != root) {
        # Split "refs/heads/branch-name" by "/" and extract branch name
        # For refs/heads/feature/foo, this produces: feature/foo
        split($2, parts, "/")
        branch = parts[3]  # Start with first part after refs/heads/
        # Rejoin remaining parts with "/" for nested branch names
        for (i = 4; i <= length(parts); i++) {
          branch = branch "/" parts[i]
        }
        print branch
      }
    }
  '
}

# Get worktree branch (same as name in our model)
get_worktree_branch() {
  echo "$1"
}

# Verify worktree directory exists
verify_worktree_exists() {
  local name="$1"
  local path
  path=$(get_worktree_path "$name")

  if [[ -z "$path" ]]; then
    error "Worktree '$name' not found"
  fi

  if [[ ! -d "$path" ]]; then
    error "Worktree directory '$path' does not exist"
  fi
}

# Check if on protected branch
is_protected_branch() {
  local branch
  branch=$(git branch --show-current)

  [[ "$branch" == "main" ]] || [[ "$branch" == "master" ]]
}

ensure_not_protected_branch() {
  if is_protected_branch; then
    error "Cannot perform this operation on main/master branch"
  fi
}

# Check for uncommitted changes
has_uncommitted_changes() {
  # Check for modified/staged files
  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    return 0
  fi

  # Check for untracked files
  if [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
    return 0
  fi

  return 1
}

# Extract unique directories from a list of file paths
# This is useful for fzf file selection - allows users to select entire directories
# Input: $1 = newline-separated list of file paths (e.g., "src/foo.js\nsrc/bar.js\nlib/baz.js")
# Output: newline-separated list of unique directories, sorted (e.g., "lib\nsrc")
# Example:
#   dirs=$(extract_directories "$all_files")
extract_directories() {
  local files="$1"
  local directories=()

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    local dir
    dir=$(dirname "$file")
    # Skip current directory "." - only include actual subdirectories
    if [[ "$dir" != "." ]]; then
      directories+=("$dir")
    fi
  done <<< "$files"

  # Sort and deduplicate directories
  printf '%s\n' "${directories[@]}" | sort -u
}

# Expand directory selections from fzf into individual files
# When users select a directory in fzf (shown with trailing /), this expands it to all files within
# Input: $1 = selected items from fzf (newline-separated, dirs have trailing /)
#        $2 = all available files (newline-separated)
# Output: expanded list of files (newline-separated)
# Example:
#   If user selects "commands/" and "lib/foo.sh":
#   Input selected: "commands/\nlib/foo.sh"
#   Input all_files: "commands/status.sh\ncommands/apply.sh\nlib/foo.sh"
#   Output: "commands/status.sh\ncommands/apply.sh\nlib/foo.sh"
expand_directory_selections() {
  local selected="$1"
  local all_files="$2"
  local result=()

  while IFS= read -r item; do
    [[ -z "$item" ]] && continue

    # Check if it's a directory (fzf displays dirs with trailing /)
    if [[ "$item" == */ ]]; then
      # Remove trailing slash for pattern matching
      local dir="${item%/}"
      # Add all files that start with "dir/" to result
      while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if [[ "$file" == "${dir}/"* ]]; then
          result+=("$file")
        fi
      done <<< "$all_files"
    else
      # It's an individual file, add it directly
      result+=("$item")
    fi
  done <<< "$selected"

  # Output deduplicated results
  printf '%s\n' "${result[@]}"
}

# Get upstream branch for current directory (must be called from within a git worktree)
# Output: upstream branch name (e.g., "origin/main") or empty string if no upstream
get_upstream_branch() {
  git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo ""
}

# Get ahead/behind counts for current branch relative to upstream
# Must be called from within a git worktree (use pushd first if needed)
# Output: two lines - "ahead <count>" and "behind <count>"
# Example usage:
#   while IFS=' ' read -r key value; do
#     if [[ "$key" == "ahead" ]]; then ahead="$value"; fi
#     if [[ "$key" == "behind" ]]; then behind="$value"; fi
#   done < <(get_ahead_behind_counts)
get_ahead_behind_counts() {
  local upstream
  upstream=$(get_upstream_branch)

  # If no upstream is configured, return zeros
  if [[ -z "$upstream" ]]; then
    echo "ahead 0"
    echo "behind 0"
    return
  fi

  # Count commits in HEAD that aren't in upstream (@{u}..HEAD)
  local ahead
  ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
  # Count commits in upstream that aren't in HEAD (HEAD..@{u})
  local behind
  behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")

  echo "ahead $ahead"
  echo "behind $behind"
}

# Get count of uncommitted files in a worktree
# Counts both modified tracked files and untracked files
# Input: $1 = absolute path to worktree directory
# Output: count of uncommitted files (integer)
# Example:
#   count=$(get_worktree_uncommitted_count "/path/to/worktree")
get_worktree_uncommitted_count() {
  local worktree_path="$1"
  local count=0

  if [[ -d "$worktree_path" ]]; then
    if pushd "$worktree_path" > /dev/null 2>&1; then
      # git status --porcelain outputs one line per changed file
      # Count lines to get total number of uncommitted changes
      count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
      popd > /dev/null 2>&1
    fi
  fi

  echo "$count"
}

# Get count of commits in a worktree that are not in ww-working
# This tells you how many commits the worktree has made that haven't been applied to ww-working
# Input: $1 = absolute path to worktree directory
# Output: count of commits (integer)
# Example:
#   count=$(get_worktree_commit_count "/path/to/worktree")
#   if [[ "$count" -gt 0 ]]; then echo "Has $count unapplied commits"; fi
get_worktree_commit_count() {
  local worktree_path="$1"
  local count=0

  if [[ -d "$worktree_path" ]]; then
    if pushd "$worktree_path" > /dev/null 2>&1; then
      # git rev-list WW_BRANCH..HEAD lists commits in HEAD not in WW_BRANCH
      # --count just gives us the number
      count=$(git rev-list --count "${WW_BRANCH}..HEAD" 2>/dev/null || echo "0")
      popd > /dev/null 2>&1
    fi
  fi

  echo "$count"
}

# Execute a git command in a worktree directory
# Usage: run_in_worktree "/path/to/worktree" "git status"
# Returns: exit code of the command
run_in_worktree() {
  local worktree_path="$1"
  shift
  local result=1

  if [[ -d "$worktree_path" ]]; then
    if pushd "$worktree_path" > /dev/null 2>&1; then
      "$@"
      result=$?
      popd > /dev/null 2>&1
    fi
  fi

  return $result
}

# Check if a branch has been merged into another branch
# Usage: is_branch_merged "feature-branch" "main"
# Returns: 0 if merged, 1 if not merged
is_branch_merged() {
  local branch="$1"
  local target_branch="$2"

  if git branch --merged "$target_branch" 2>/dev/null | grep -q "^[*+ ]*${branch}$"; then
    return 0
  else
    return 1
  fi
}

# Get the main branch name (main or master)
# Checks in order: origin/main, origin/master, local main, local master
# Output: branch name (e.g., "main" or "master") or empty if not found
get_main_branch() {
  if git show-ref --verify --quiet refs/remotes/origin/main; then
    echo "main"
  elif git show-ref --verify --quiet refs/remotes/origin/master; then
    echo "master"
  elif git show-ref --verify --quiet refs/heads/main; then
    echo "main"
  elif git show-ref --verify --quiet refs/heads/master; then
    echo "master"
  else
    echo ""
  fi
}

# Get the main branch reference for checking (with origin if available)
# Output: "origin/main", "origin/master", "main", "master", or empty
get_main_branch_ref() {
  if git show-ref --verify --quiet refs/remotes/origin/main; then
    echo "origin/main"
  elif git show-ref --verify --quiet refs/remotes/origin/master; then
    echo "origin/master"
  elif git show-ref --verify --quiet refs/heads/main; then
    echo "main"
  elif git show-ref --verify --quiet refs/heads/master; then
    echo "master"
  else
    echo ""
  fi
}

# Validate git command output
# Usage: validate_git_output "$output" "command description"
# Returns: 0 if valid, exits with error if invalid
validate_git_output() {
  local output="$1"
  local description="$2"

  # Check for common git error patterns
  if [[ "$output" =~ "fatal:" ]] || [[ "$output" =~ "error:" ]]; then
    error "Git command failed: $description"
  fi

  return 0
}

# Run fzf with standard options
# Usage: run_fzf "prompt text" <<< "$file_list"
run_fzf() {
  local prompt="$1"
  fzf $FZF_OPTS --prompt="${prompt}"
}

# Get a summary line for a worktree (for fzf display)
# Input: $1 = worktree name
# Output: formatted status string like "  - 3 uncommitted, 2 commits [not applied] [2 ahead]"
get_worktree_status_summary() {
  local name="$1"
  local repo_root
  repo_root=$(get_repo_root)

  local path
  path=$(get_worktree_path "$name")

  if [[ -z "$path" ]]; then
    echo " - MISSING"
    return
  fi

  local abs_path="${repo_root}/${path}"

  if [[ ! -d "$abs_path" ]]; then
    echo " - MISSING"
    return
  fi

  # Get uncommitted count
  local uncommitted_count
  uncommitted_count=$(get_worktree_uncommitted_count "$abs_path")

  # Get commit count
  local commit_count
  commit_count=$(get_worktree_commit_count "$abs_path")

  # Check for assignment commits
  local applied_status=""
  local assignment_commits
  assignment_commits=$(git log ${WW_BRANCH} --oneline --grep="ww: assign .* to ${name}" --max-count=50 2>/dev/null || echo "")

  if [[ -n "$assignment_commits" ]]; then
    applied_status=" [applied]"
  elif [[ "$commit_count" -gt 0 ]]; then
    applied_status=" [not applied]"
  fi

  # Get push status
  local push_status=""
  if [[ "$commit_count" -gt 0 ]]; then
    if pushd "$abs_path" > /dev/null 2>&1; then
      local upstream
      upstream=$(get_upstream_branch)

      if [[ -n "$upstream" ]]; then
        local ahead behind
        while IFS=' ' read -r key value; do
          if [[ "$key" == "ahead" ]]; then
            ahead="$value"
          elif [[ "$key" == "behind" ]]; then
            behind="$value"
          fi
        done < <(get_ahead_behind_counts)

        if [[ "$ahead" -gt 0 ]]; then
          push_status=" [${ahead} ahead]"
        fi
      else
        push_status=" [not pushed]"
      fi
      popd > /dev/null 2>&1
    fi
  fi

  # Build status parts
  local status_parts=()
  if [[ "$uncommitted_count" -gt 0 ]]; then
    status_parts+=("${uncommitted_count} uncommitted")
  fi
  if [[ "$commit_count" -gt 0 ]]; then
    status_parts+=("${commit_count} commit(s)")
  fi

  # Build final status string
  local status_str=""
  if [[ ${#status_parts[@]} -gt 0 ]]; then
    status_str=" - $(IFS=", "; echo "${status_parts[*]}")${applied_status}${push_status}"
  elif [[ -n "$push_status" ]] || [[ -n "$applied_status" ]]; then
    status_str="${applied_status}${push_status}"
  else
    status_str=" - EMPTY"
  fi

  echo "$status_str"
}

# Select worktree interactively with fzf
# Shows worktree status information for context
# Returns: selected worktree name (just the name, not the status)
# Usage: worktree=$(select_worktree_interactive)
select_worktree_interactive() {
  if ! command -v fzf > /dev/null 2>&1; then
    error "fzf is required for interactive selection. Install fzf or specify worktree name directly."
  fi

  local names
  names=$(list_worktree_names)

  if [[ -z "$names" ]]; then
    error "No worktrees available. Create one with 'ww create <name>'"
  fi

  # Build worktree list with status
  local worktree_list=""
  while IFS= read -r name; do
    local status
    status=$(get_worktree_status_summary "$name")
    worktree_list+="${name}${status}"$'\n'
  done <<< "$names"

  # Run fzf and extract just the worktree name (first field)
  echo "$worktree_list" | run_fzf "Search worktrees: " | awk '{print $1}'
}

# Select an assigned file from a worktree interactively with fzf
# Shows files that have been assigned to this worktree (via assignment commits)
# Input: $1 = worktree name
# Returns: selected file path
# Usage: file=$(select_assigned_file_interactive "worktree-name")
select_assigned_file_interactive() {
  local worktree_name="$1"

  if ! command -v fzf > /dev/null 2>&1; then
    error "fzf is required for interactive selection. Install fzf or specify file path directly."
  fi

  # Find all assignment commits for this worktree
  local assigned_files=""
  while IFS= read -r sha; do
    if [[ -n "$sha" ]]; then
      # Get the commit message
      local msg
      msg=$(git log -1 --format="%s" "$sha" 2>/dev/null)

      # Extract filename from "ww: assign <filename> to <worktree>" format
      # Using sed to extract the part between "assign " and " to"
      local filename
      filename=$(echo "$msg" | sed -n 's/^ww: assign \(.*\) to .*$/\1/p')

      if [[ -n "$filename" ]]; then
        assigned_files+="${filename}"$'\n'
      fi
    fi
  done < <(git log --format="%H" --grep="ww: assign .* to ${worktree_name}$" ${WW_BRANCH} --max-count=100 2>/dev/null)

  if [[ -z "$assigned_files" ]]; then
    error "No files assigned to '${worktree_name}'"
  fi

  # Show files in fzf
  echo "$assigned_files" | run_fzf "Search files: "
}
