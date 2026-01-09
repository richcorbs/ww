# ww - Worktree Workflow Manager

A GitButler-inspired workflow using native git worktrees, allowing you to work on multiple features simultaneously while keeping changes organized in a dedicated staging branch.

## Features

- **Modernized git workflow**: Make changes and then decide which worktree/branch to assign them to
- **Uses standard git commands**: Be confident that your changes are safe
- **Dedicated staging branch**: All work happens in `ww-working`, keeping `main` clean
- **Interactive file selection**: Use fzf for visual multi-select file assignment
- **File-level assignment**: Selectively assign files to different worktrees
- **Directory assignment**: Assign all changed files in a directory or all files at once
- **Selective staging**: Stage specific files in worktrees before committing
- **Smart commits**: Automatically detects staged files and commits accordingly
- **Commit tracking**: Track which commits have been applied between branches
- **Safe operations**: Work in isolation without affecting your main branch
- **Simple CLI**: Single `ww` command with intuitive subcommands
- **Simplified worktree creation**: `ww create <branch>` - branch name is the worktree name

## Installation

### Requirements

- Git 2.5 or higher
- jq (JSON processor)
- Bash 4+
- fzf (fuzzy finder) - For interactive file selection
- gh (GitHub CLI) - Optional, for PR links in status and `ww pr` command

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/richcorbs/ww/main/install.sh | bash
```

The installer will check dependencies, download ww to `~/.local/share/ww`, and create a symlink in `~/.local/bin`.

### Install for Development

```bash
# Clone the repository
git clone https://github.com/richcorbs/ww.git
cd ww

# Run the installer (symlinks to your clone)
./install.sh
```

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/richcorbs/ww/main/uninstall.sh | bash
```

## Quick Start

```bash
# 1. Initialize in your repository
cd your-repo
ww init
# This creates ww-working branch and checks it out

# 2. Make some changes
# ... edit files ...

# 3. Check status
ww status
# Output:
#   Working in: ww-working
#
#   Unassigned changes:
#     M  app/models/user.rb
#     A  app/controllers/sessions_controller.rb
#     A  app/controllers/passwords_controller.rb
#
#   Worktrees:
#     (none)
#
#     Use 'ww create <branch>' to create a worktree

# 4. Create a worktree for a feature
ww create feature/user-auth

# 5. Assign files to the worktree (opens interactive fzf selector)
ww assign feature/user-auth
# OR assign files directly:
# ww assign feature/user-auth app/models/user.rb      # Single file
# ww assign feature/user-auth app/controllers/        # Directory
# ww assign feature/user-auth .                       # All files

# 6. Commit changes in the worktree
ww commit feature/user-auth "Add user authentication"

# 7. Push the feature branch
ww push feature/user-auth

# 8. Create pull request
ww pr feature/user-auth  # Opens GitHub PR creation page in browser

# 9. After PR is merged to main, update ww-working
ww update
# This merges main into ww-working and automatically cleans up merged worktrees
```

## How It Works

### The ww-working Branch

Instead of working directly in `main`, all your work happens in a dedicated `ww-working` branch:

1. **Initialize**: `ww init` creates and checks out `ww-working`
2. **Work**: Make all changes in `ww-working` but you don't have to. You can still checkout and branch off of `main` if you need to.
3. **Assign**: `ww-working` stays in sync when files are assigned to worktrees
4. **Worktrees**: `ww` automatically branches off of `ww-working` for you
5. **Merge**: When features are done, merge to `main` via normal git PR workflow
6. **Update**: Use `ww update` to merge `main` back into `ww-working` and cleanup your local branches and worktrees

This keeps your `main` branch pristine while giving you a flexible staging area.

### Directory Structure

```
your-repo/
  .worktrees/              ← worktrees (gitignored)
    feature-auth/
    bugfix-123/
  .worktree-flow/          ← metadata (gitignored)
    metadata.json
    abbreviations.json
  app/
  ...
```

## Commands

### `ww init`

Initialize worktree workflow in the current repository.

```bash
ww init
```

This:
- Creates and checks out `ww-working` branch
- Creates `.worktree-flow/` directory for metadata (gitignored)
- Creates `.worktrees/` directory (gitignored)
- Adds entries to `.gitignore`

### `ww status`

Show unassigned changes and the status of each worktree.

```bash
ww status
```

Output:
```
  Working in: ww-working

  Unassigned changes:
    ab  M  app/models/user.rb
    cd  A  app/controllers/sessions_controller.rb
    ef  ?  config/routes.rb

  Worktrees:
    feature-auth (feature/user-auth) - 2 uncommitted, 1 commit(s)
      PR #123: https://github.com/user/repo/pull/123
      gh  M  app/models/user.rb
      ij  A  app/services/auth_service.rb
    bugfix-login (bugfix/login-issue) - 0 uncommitted, 0 commit(s)
```

Shows:
- Unassigned changes with two-letter abbreviations for making assignments easy
- Worktree status with commit counts and unstaged changes
- Associated PR links (requires GitHub CLI)
- Uncommitted files in each worktree with git status codes

### `ww switch [branch]`

Switch between branches. If no branch is specified, toggles between `ww-working` and `main`.

```bash
# Toggle between ww-working and main
ww switch

# Switch to a specific branch
ww switch develop
```

This is a convenient shortcut for `git checkout` with smart defaults:
- If on `ww-working`: switches to `main`
- If on any other branch: switches to `ww-working`

### `ww create <branch>`

Create a new worktree branching from `ww-working`. The branch name is used as the worktree name.

```bash
ww create feature/user-auth    # Creates .worktrees/feature/user-auth/
ww create bugfix/issue-123     # Creates .worktrees/bugfix/issue-123/
```

Arguments:
- `branch`: Branch name (also used as worktree name)

### `ww list`

List all worktrees with their status.

```bash
ww list
```

### `ww assign <worktree> [file|directory|.]`

Assign files to a worktree. Opens fzf for interactive multi-select if no file is specified.

```bash
# Interactive selection with fzf (recommended)
ww assign feature/user-auth

# Or specify files directly:
ww assign feature/user-auth app/models/user.rb    # Single file
ww assign feature/user-auth app/models/           # Directory
ww assign feature/user-auth .                     # All files
```

What happens:
1. Files remain in `ww-working` (committed)
2. Changes are copied to the worktree (uncommitted)
3. Files are removed from "unassigned" list

### `ww stage <worktree> <file|directory|.>`

Stage files in a worktree for selective commits.

```bash
ww stage feature/user-auth app/models/user.rb    # Single file
ww stage feature/user-auth app/models/           # Directory
ww stage feature/user-auth .                     # All files
```

Use this when you want to commit only specific files from a worktree.

### `ww unstage <worktree> <file|.>`

Unstage files in a worktree (equivalent to git reset). Removes files from the staging area but keeps the changes as uncommitted.

```bash
ww unstage feature/user-auth app/models/user.rb    # Single file
ww unstage feature/user-auth .                     # All files
```

This is the opposite of `ww stage` - useful when you've staged files but want to unstage them without losing changes.

### `ww commit <worktree> <message>`

Commit changes in a worktree without having to cd into it.

```bash
ww commit feature/user-auth "Add user authentication"
```

The commit command is staging-aware:
- If files are staged (via `ww stage`), commits only those files
- If no files are staged, auto-stages all changes and commits them
- Shows clear messaging about what's being committed

### `ww uncommit <worktree>`

Uncommit the last commit in a worktree (brings changes back to uncommitted).

```bash
ww uncommit feature/user-auth
```

### `ww unassign <worktree> <file|.>`

Unassign file(s) from a worktree - reverts the commit in `ww-working` and removes changes from the worktree.

```bash
ww unassign feature/user-auth app/models/user.rb    # Single file
ww unassign feature/user-auth .                     # All assigned files
```

The file(s) will show up as "unassigned" again.

### `ww apply <worktree>`

Apply (cherry-pick) commits from a worktree to ww-working. This means that all of the code will be available for further development or testing in ww-working.

```bash
ww apply feature-auth
```

### `ww unapply <worktree>`

Unapply (revert) commits that were applied from a worktree. This means that you effectively remove the worktree changeset from the ww-working branch and those changes are no longer available for further development or testing in ww-working. You can add them back to ww-working with `ww apply <worktree>`.

```bash
ww unapply feature-auth
```

### `ww push <worktree>`

Push a worktree's branch to the remote.

```bash
ww push feature-auth
```

### `ww pr <worktree>`

Open the GitHub PR creation page for a worktree's branch in your browser. If the branch hasn't been pushed yet, `ww` will push it automatically.

```bash
ww pr feature-auth
```

This command:
1. Checks if the branch is pushed to origin (pushes if not)
2. Detects the worktree's branch name
3. Constructs the GitHub PR creation URL
4. Opens it in your default browser

Works with both HTTPS and SSH remote URLs.

### `ww update [branch]`

Update `ww-working` with another branch (default: main). Automatically detects and cleans up worktrees whose branches have been merged.

```bash
ww update           # Update from main and clean up merged worktrees
ww update develop   # Update from develop
```

What it does:
1. Fetches latest changes from origin
2. Updates local branch from origin
3. Merges branch into `ww-working`
4. **Automatically detects worktrees with merged branches**
5. **Removes merged worktrees**
6. **Deletes corresponding remote branches**

This is now a one-stop command for staying in sync and cleaning up finished work.

### `ww remove <worktree> [--force]`

Remove a worktree and clean up metadata.

```bash
ww remove feature-auth
ww remove bugfix --force
```

## Workflow Examples

### Basic Feature Development

```bash
# Start fresh
$ ww init

  ✓ Created .worktree-flow directory
  ✓ Created .worktrees directory
  ✓ Updated .gitignore
  ✓ Created ww-working branch
  ✓ Worktree workflow initialized

# Create feature worktree
$ ww create feature/auth

  ✓ Created worktree 'feature/auth' at .worktrees/feature/auth
  ✓ Branched from ww-working as feature/auth

# Make changes in ww-working
# ... edit files ...

$ ww status

  Working in: ww-working

  Unassigned changes:
    M  app/models/user.rb
    A  app/controllers/auth_controller.rb

  Worktrees:
    feature/auth (feature/auth) - 0 uncommitted, 0 commit(s)

# Assign files interactively with fzf
$ ww assign feature/auth

  Select files to assign (TAB to select, ENTER to confirm)...
  # fzf opens, select both files

  ✓ Assigned 2 file(s) to 'feature/auth' and committed to ww-working

# Commit in worktree
$ ww commit feature/auth "Add authentication"

  No files staged, auto-staging all changes...
  ✓ Committed changes in 'feature/auth'

# Push and create PR
$ ww push feature/auth

  ✓ Pushed branch 'feature/auth' to origin

$ ww pr feature/auth

  Opening PR creation page for branch 'feature/auth'...
  URL: https://github.com/user/repo/compare/main...feature/auth?expand=1
  ✓ PR page opened for 'feature/auth'

# After PR is merged to main, update
$ ww update

  Updating ww-working with 'main'...
  Fetching latest changes from origin...
  Updating local main from origin/main...
  ✓ Successfully updated ww-working with 'main'
  Merge commit: a1b2c3d
  Checking for merged branches...

  Branch 'feature/auth' has been merged into main
    Removing worktree 'feature/auth'...
    Deleting remote branch 'feature/auth'...
    ✓ Cleaned up 'feature/auth'

  ✓ Cleaned up 1 merged worktree(s)
```

### Working on Multiple Features

```bash
ww create feature/auth
ww create feature/api-refactor

# Make changes
# ... edit multiple files ...

# Assign to different features using fzf
ww assign feature/auth         # Select auth-related files
ww assign feature/api-refactor # Select API files

# Commit separately
ww commit feature/auth "Add authentication"
ww commit feature/api-refactor "Refactor API base"

# Push and create PRs
ww pr feature/auth
ww pr feature/api-refactor
```

### Assigning Directories

```bash
ww create feature/model-refactor

# Make changes to multiple files in app/models/
# ... edit files ...

# Assign entire directory
ww assign feature/model-refactor app/models/

# Commit
ww commit feature/model-refactor "Refactor models"
```

### Selective Staging and Commits

```bash
ww create feature/multi-part

# Assign files interactively
ww assign feature/multi-part

# Stage and commit only specific files
ww stage feature/multi-part app/models/user.rb
ww commit feature/multi-part "Add user model"

# Stage and commit remaining files
ww stage feature/multi-part .
ww commit feature/multi-part "Add controllers and views"
```

Or commit everything at once without staging:
```bash
# If no files are staged, commit auto-stages all changes
ww commit feature/multi-part "Implement complete feature"
```

### Undoing Mistakes

```bash
# Assigned wrong file
ww unassign feature/user-auth app/models/admin.rb

# Committed too early in worktree
ww uncommit feature/user-auth

# Unassign all files from a worktree
ww unassign feature/user-auth .
```

### Syncing After Merges

```bash
# Your feature branches got merged to main on GitHub
# Just run update - it handles everything automatically

ww update

# Output:
# ✓ Successfully updated ww-working with 'main'
# ✓ Branch 'feature/user-auth' has been merged into main
#   - Removing worktree 'auth'...
#   - Deleting remote branch 'feature/user-auth'...
#   ✓ Cleaned up 'auth'
# ✓ Cleaned up 1 merged worktree(s)

# Done! ww-working is updated and merged work is cleaned up
# Continue working on new features
```

## Tips

1. **Always work in `ww-working`** - Don't make changes in `main`
2. **Use `ww switch` to quickly toggle** between `ww-working` and `main`
3. **Run `ww status` often** to see your abbreviations, worktree state, and uncommitted files
4. **Use directory assignment** for bulk file operations: `ww assign app/models feature-x`
5. **Use selective staging** for multi-part commits: `ww stage <worktree> <file>` then `ww commit`
6. **Skip staging for quick commits** - `ww commit` auto-stages everything if nothing is staged
7. **Update regularly** after merging features to main: `ww update`
8. **Use `ww unassign`** to correct assignment mistakes
9. **Commit small, logical changes** in worktrees for clearer history
10. **Use abbreviated commands** for speed: `ww as` (assign), `ww ap` (apply), `ww cr` (create)

## Troubleshooting

### Command not found: ww

Make sure the installation directory is in your PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add this to your `~/.bashrc` or `~/.zshrc`.

### Not on ww-working branch

`ww status` will warn you if you're not on `ww-working`. Switch back with:

```bash
git checkout ww-working
```

### Failed to apply patch

This can happen if files have diverged. Try:
1. Committing changes in the worktree first
2. Using `ww apply` if needed
3. Resolving any conflicts

### Merge conflicts when updating

When running `ww update`, you may encounter merge conflicts. Resolve them normally:

```bash
# Fix conflicts in files
git add .
git commit
```

## Comparison to GitButler

**Similar:**
- Work in one staging area
- Selectively assign files to branches
- Multiple features in parallel
- Virtual branch concept (ww-working)

**Different:**
- Uses native git worktrees
- Explicit commit on assign (no hidden commits)
- Two-letter abbreviations for file selection
- Pure bash (no Rust/Tauri)
- File/directory-level (not hunk-level) assignment
- Dedicated staging branch instead of virtual layer

## License

MIT

## Contributing

Contributions welcome! The code is organized as:

- `bin/ww` - Main dispatcher
- `commands/*.sh` - Subcommand implementations
- `lib/ww-lib.sh` - Shared library functions
- `lib/abbreviations.sh` - Abbreviation generation

## Development

To hack on `wW`:

```bash
cd ~/Code/wW

# Edit files
# ... make changes ...

# Run tests (one command - fast and local)
./run-tests.sh

# Test without installing
./bin/ww status

# When ready, run install
./install.sh
```

### Testing

Run the test suite with a single command:

```bash
./run-tests.sh
```

- ✅ Fast: All tests run locally in ~2 seconds
- ✅ Isolated: Creates fresh test repos for each test
- ✅ Auto-cleanup: Removes test artifacts automatically
- ✅ No setup: Just run the script

Requirements: `git` and `jq` (the script will check and tell you if anything is missing)
