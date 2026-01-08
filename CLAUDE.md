# CLAUDE.md - Essential Context for Future Sessions

## Project Philosophy

**Core Concept**: `wt` implements a "work in staging, organize later" workflow. Developers work on a shared `worktree-staging` branch and use `wt assign` to organize changes into separate worktrees when ready to create PRs.

**Key Principle**: Minimize friction - make it easy to "just start coding" and organize later.

## Major Simplifications (Important History)

1. **Removed abbreviation system** (Jan 2026) - Originally had hash-based two-letter abbreviations (aa-zz) for files. Tried sequential abbreviations but they shifted after assignment. Replaced entirely with fzf interactive selection.
2. **Simplified worktree creation** - Changed from `wt create <name> <branch> [path]` to just `wt create <branch>`. Branch name IS the worktree name.
3. **Auto-create worktrees** - Commands like `wt assign` now create worktrees automatically if they don't exist.

## Critical Architecture Decisions

### Worktree Naming
- Branch name = worktree name (always)
- Path is always `.worktrees/<branch>` (slashes in branch names create subdirectories)
- Example: `wt create feature/auth` creates `.worktrees/feature/auth/`

### Command Argument Order
- `wt assign <worktree> [file]` (worktree FIRST, file second or omit for fzf)
- `wt commit <worktree> [message]` (worktree FIRST, always uses fzf, message pre-fills prompt)
- `wt unassign <worktree> [file]` (worktree FIRST, file optional - defaults to all if omitted)

### Status Display Format Swap
- Git's `git status --porcelain` returns XY format (X=staged, Y=unstaged)
- We display as YX for left-to-right visual progression: unstaged → staged
- `M ` (git's format: staged and modified) displays as ` M`
- ` M` (git's format: unstaged modified) displays as `M `
- `A ` (git's format: staged addition) displays as ` A`
- `MM` (git's format: staged and also modified) displays as `MM`
- See `commands/status.sh` lines 92-108 and 298-315
- Also applied in `commands/commit.sh` for fzf display

### Auto-Status
- All commands that modify state show `wt status` after success
- Pattern: `source "${WT_ROOT}/commands/status.sh" && cmd_status`
- Commands: assign, unassign, commit, uncommit, apply, unapply, push, pr, sync, create

### fzf Integration
- All file selection uses fzf multi-select when file argument omitted
- "[All files]" option always available as first item
- Vim keybindings: Ctrl+j/k (up/down), Ctrl+d/u (page down/up)
- TAB to select/deselect files, ENTER to confirm
- Pattern in assign and commit commands
- `wt commit` marks staged files with [S] indicator
- Directory selection supported with "DIR" prefix

## File Structure

### Core Files
- `bin/wt` - Main entry point, routes to commands
- `lib/wt-lib.sh` - Core functions, metadata management
- `lib/abbreviations.sh` - **REMOVED** (was gutted in Jan 2026, no longer needed)
- `commands/*.sh` - All command implementations

### Metadata
- `.worktree-flow/metadata.json` - Tracks worktrees (name, branch, path)
- `.worktree-flow/abbreviations.json` - No longer used (can be removed)

### Key Commands to Know
- `status.sh` - Shows applied/pushed indicators with YX format, no redundant branch display
- `assign.sh` - Auto-creates worktrees, fzf selection, handles deleted files
- `unassign.sh` - Uses patches to restore files (not git revert), avoids conflicts
- `create.sh` - Simplified to single argument (branch name = worktree name)
- `sync.sh` - Merges main into worktree-staging, auto-cleans merged branches
- `commit.sh` - Always uses fzf with [S] indicator for staged files, message pre-fill support

## Status Indicators

### Applied Status (lines 180-207 in status.sh)
- Uses `git patch-id` to detect if commits in worktree exist in worktree-staging
- `[applied]` = all commits cherry-picked
- `[not applied]` = some commits not yet in staging
- **Note**: Only shows when there are commits to potentially apply

### Push Status (lines 209-234 in status.sh)
- `[pushed]` = synced with remote
- `[N ahead]` = local commits not pushed
- `[N behind]` = remote commits not pulled
- `[not pushed]` = no upstream tracking branch

### Staged Status
- YX format shows unstaged then staged character
- Visual progression left-to-right

## Dependencies

### Required
- bash
- git (with worktree support)

### Optional but Enhanced
- `fzf` - Interactive file selection (required for interactive mode)
- `gh` (GitHub CLI) - PR creation, PR status in `wt status`

## Testing

**Run tests**: `./run-tests.sh`

**Test structure**:
- `tests/test-helpers.sh` - Assertion helpers
- `tests/test-all.sh` - Comprehensive test suite (NEEDS UPDATING for recent changes)
- `tests/test-abbreviations.sh` - Abbreviated command tests (cr, ls, st, as, etc.)
- Tests create isolated repos in `test-repos/`

**Key test patterns**:
- Use `create_test_repo()` for isolated test environments
- Commands redirect to `/dev/null 2>&1` to suppress output
- Use `assert_success`, `assert_file_exists`, `assert_contains`

## Common Patterns

### Reading uncommitted files
```bash
git status --porcelain 2>/dev/null
```

### Swapping status for display
```bash
local X="${status_code:0:1}"  # staged
local Y="${status_code:1:1}"  # unstaged
local display_status="${Y}${X}"  # swap for visual progression
```

### fzf with "[All files]" option
```bash
local file_list="*  [All files]"$'\n'
# ... add files ...
selected=$(echo "$file_list" | fzf --multi | sed 's/^.  //')
if echo "$selected" | grep -q "\[All files\]"; then
  # Handle all files
fi
```

### Filtering files for staging/unstaging
```bash
# For staging: skip fully-staged files (Y == space)
if [[ "$Y" == " " ]]; then
  continue
fi

# For unstaging: only show staged files (X != space)
if [[ "$X" != " " ]]; then
  echo "$line"
fi
```

## What NOT to Do

1. **Don't bring back abbreviations** - Tried hash-based and sequential systems, both were too complex
2. **Don't change argument order** - `wt assign <worktree> <file>` is settled
3. **Don't skip auto-status** - Users expect to see status after changes
4. **Don't use XY format for display** - Always swap to YX for visual progression
5. **Don't require fzf** - Commands should work with explicit file arguments too
6. **Don't display branch separately** - Worktree name and branch name are identical now

## Recent Changes (as of Jan 2026)

- Swapped file status display to YX format in status.sh, commit.sh
- Removed abbreviations.sh entirely and all `get_filepath_from_abbrev` calls
- **Removed wt stage and wt unstage commands** - simplified workflow uses only wt commit
- Refactored wt commit to always use fzf with [S] indicator for staged files
- wt commit now pre-fills message prompt if message provided via command line
- Fixed merge conflict in unstage.sh (removed old abbreviation code)
- Refactored wt unassign to use patches instead of git revert (avoids conflicts)
- Fixed wt assign to handle deleted files properly
- Added directory selection to fzf in all commands
- Fixed applied/not applied indicator to check for assignment commits in worktree-staging
- Removed redundant branch display from wt status (show name only)
- Test suite needs updating for simplified commands

## Known Issues / TODO

- Test suite needs updates for recent changes (wt create simplified, abbreviations removed)
- Need to add directory selection to fzf (allow selecting entire directories)
- Applied/not applied indicator concept needs clarification with user

## If You Need to Make Changes

1. **Read existing commands first** - Patterns are consistent across all commands
2. **Test with real worktrees** - The test suite is helpful but manual testing catches UX issues
3. **Preserve auto-status** - Add status display after successful operations
4. **Use fzf patterns** - Follow existing fzf implementations for consistency
5. **Update DEVELOPMENT.md** - For contributor-facing documentation
6. **Update tests** - Keep test suite in sync with changes

This context should help future Claude sessions understand the project's evolution and current state without repeating past mistakes.
