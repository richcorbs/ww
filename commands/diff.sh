#!/usr/bin/env bash
# Review diffs in a worktree with interactive stage/unstage

show_help() {
  cat <<EOF
Usage: ww diff [worktree]

Review file diffs in a worktree with interactive preview.
Shows files that differ from main with a live diff preview.

Keybindings:
  s         Toggle stage/unstage for current file
  enter     Exit
  esc       Exit

Arguments:
  worktree    Name of the worktree (optional - will prompt with fzf)

Options:
  -h, --help    Show this help message

Examples:
  ww diff                    # Select worktree, then review diffs
  ww diff feature-auth       # Review diffs in feature-auth worktree
EOF
}

cmd_diff() {
  local worktree_name=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        if [[ -z "$worktree_name" ]]; then
          worktree_name="$1"
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

  # Check for fzf
  if ! command -v fzf > /dev/null 2>&1; then
    error "fzf is required for ww diff. Install fzf to use this command."
  fi

  local repo_root
  repo_root=$(get_repo_root)

  local worktree_path
  worktree_path=$(get_worktree_path "$worktree_name")

  local abs_worktree_path="${repo_root}/${worktree_path}"

  # Get main branch
  local main_branch
  main_branch=$(get_main_branch)
  if [[ -z "$main_branch" ]]; then
    main_branch="main"
  fi

  # Enter worktree directory
  if ! pushd "$abs_worktree_path" > /dev/null 2>&1; then
    error "Failed to enter worktree directory"
  fi

  # Create a script to get the file list with status
  # This will be called by fzf reload
  local list_script
  list_script=$(mktemp)
  cat > "$list_script" << 'LISTSCRIPT'
#!/usr/bin/env bash
cd "$1" || exit 1
main_branch="$2"

# Get files that differ from main (committed) and uncommitted changes
{
  # Uncommitted changes
  git status --porcelain 2>/dev/null | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    status_code="${line:0:2}"
    filepath="${line:3}"

    X="${status_code:0:1}"
    Y="${status_code:1:1}"
    display_status="${Y}${X}"

    if [[ "$display_status" == "  " ]]; then
      display_status=" "
    fi

    staged_indicator=""
    if [[ "$X" != " " ]] && [[ "$X" != "?" ]]; then
      staged_indicator=" [S]"
    fi

    echo "${display_status}  ${filepath}${staged_indicator}"
  done

  # Committed changes vs main (only files not in uncommitted)
  git diff --name-only "${main_branch}...HEAD" 2>/dev/null | while IFS= read -r filepath; do
    [[ -z "$filepath" ]] && continue
    # Skip if file has uncommitted changes (already shown above)
    if ! git status --porcelain "$filepath" 2>/dev/null | grep -q .; then
      echo " C  ${filepath}"
    fi
  done
}
LISTSCRIPT
  chmod +x "$list_script"

  # Create a script to toggle stage/unstage
  local toggle_script
  toggle_script=$(mktemp)
  cat > "$toggle_script" << 'TOGGLESCRIPT'
#!/usr/bin/env bash
cd "$1" || exit 1
file="$2"

# Remove status prefix and [S] suffix
file=$(echo "$file" | sed 's/^..  //' | sed 's/ \[S\]$//' | sed 's/ \[C\]$//')

# Check current status
status=$(git status --porcelain "$file" 2>/dev/null)
X="${status:0:1}"

if [[ "$X" == " " ]] || [[ "$X" == "?" ]]; then
  # Not staged - stage it
  git add "$file" 2>/dev/null
else
  # Staged - unstage it
  git reset HEAD "$file" 2>/dev/null
fi
TOGGLESCRIPT
  chmod +x "$toggle_script"

  # Build preview command - show diff against main, or file contents for new files
  local preview_cmd="cd '$abs_worktree_path' && file=\$(echo {} | sed 's/^..  //' | sed 's/ \\[S\\]\$//' | sed 's/ \\[C\\]\$//'); status=\$(git status --porcelain \"\$file\" 2>/dev/null); if [[ \"\$status\" == \\?\\?* ]] || [[ \"\$status\" == A\\ * ]]; then echo '=== NEW FILE ==='; cat \"\$file\" 2>/dev/null; else git diff HEAD -- \"\$file\" 2>/dev/null || git diff '${main_branch}' -- \"\$file\" 2>/dev/null || cat \"\$file\" 2>/dev/null; fi"

  info "Reviewing diffs in '${worktree_name}' (s=toggle stage, enter/esc=exit)"
  echo ""

  # Run fzf with preview and keybindings
  local file_list
  file_list=$("$list_script" "$abs_worktree_path" "$main_branch")

  if [[ -z "$file_list" ]]; then
    popd > /dev/null 2>&1
    rm -f "$list_script" "$toggle_script"
    warn "No changes to review in '${worktree_name}'"
    exit 0
  fi

  echo "$file_list" | fzf \
    --ansi \
    --preview "$preview_cmd" \
    --preview-window "right:60%:wrap" \
    --bind "s:execute-silent($toggle_script '$abs_worktree_path' {})+reload($list_script '$abs_worktree_path' '$main_branch')" \
    --bind "enter:abort" \
    --bind "esc:abort" \
    --header "s=toggle stage | enter/esc=exit" \
    --no-multi

  # Cleanup
  rm -f "$list_script" "$toggle_script"
  popd > /dev/null 2>&1

  echo ""
  source "${WW_ROOT}/commands/status.sh"
  cmd_status
}
