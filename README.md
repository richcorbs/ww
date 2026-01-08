# wt - Worktree Workflow Manager

A GitButler-inspired workflow using native git worktrees, allowing you to work on multiple features simultaneously while keeping changes organized in a dedicated staging branch.

## Features

- **Dedicated staging branch**: All work happens in `worktree-staging`, keeping `main` clean
- **Interactive file selection**: Use fzf for visual multi-select file assignment
- **File-level assignment**: Selectively assign files to different worktrees
- **Directory assignment**: Assign all changed files in a directory or all files at once
- **Selective staging**: Stage specific files in worktrees before committing
- **Smart commits**: Automatically detects staged files and commits accordingly
- **Commit tracking**: Track which commits have been applied between branches
- **Safe operations**: Work in isolation without affecting your main branch
- **Simple CLI**: Single `wt` command with intuitive subcommands
- **Simplified worktree creation**: `wt create <branch>` - branch name is the worktree name

## Installation

### Requirements

- Git 2.5 or higher
- jq (JSON processor)
- Bash 4+
- fzf (fuzzy finder) - For interactive file selection
- gh (GitHub CLI) - Optional, for PR links in status and `wt pr` command

### Install

```bash
# Clone the repository
git clone https://github.com/richcorbs/wt.git .
cd wt

# Run the installer
./install.sh
```

The installer will:
1. Check dependencies
2. Create a symlink to `wt` in your PATH
3. Verify the installation

## Quick Start

```bash
# 1. Initialize in your repository
cd your-repo
wt init
# This creates worktree-staging branch and checks it out

# 2. Make some changes
# ... edit files ...

# 3. Check status
wt status
# Output:
#   Working in: worktree-staging
#
#   Unassigned changes:
#     M  app/models/user.rb
#     A  app/controllers/sessions_controller.rb
#     A  app/controllers/passwords_controller.rb
#
#   Worktrees:
#     (none)
#
#     Use 'wt create <branch>' to create a worktree

# 4. Create a worktree for a feature
wt create feature/user-auth

# 5. Assign files to the worktree (opens interactive fzf selector)
wt assign feature/user-auth
# OR assign files directly:
# wt assign feature/user-auth app/models/user.rb      # Single file
# wt assign feature/user-auth app/controllers/        # Directory
# wt assign feature/user-auth .                       # All files

# 6. Commit changes in the worktree
wt commit feature/user-auth "Add user authentication"

# 7. Push the feature branch
wt push feature/user-auth

# 8. Create pull request
wt pr feature/user-auth  # Opens GitHub PR creation page in browser

# 9. After PR is merged to main, sync worktree-staging
wt sync
# This merges main into worktree-staging and automatically cleans up merged worktrees
```

## How It Works

### The worktree-staging Branch

Instead of working directly in `main`, all your work happens in a dedicated `worktree-staging` branch:

1. **Initialize**: `wt init` creates and checks out `worktree-staging`
2. **Work**: Make all changes in `worktree-staging` but you don't have to. You can still checkout and branch off of `main` if you need to.
3. **Assign**: `worktree-staging` stays in sync when files are assigned to worktrees
4. **Worktrees**: `wt` automatically branches off of `worktree-staging` for you
5. **Merge**: When features are done, merge to `main` via normal git PR workflow
6. **Sync**: Use `wt sync` to merge `main` back into `worktree-staging` and cleanup your local branches and worktrees

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

### `wt init`

Initialize worktree workflow in the current repository.

```bash
wt init
```

This:
- Creates and checks out `worktree-staging` branch
- Creates `.worktree-flow/` directory for metadata (gitignored)
- Creates `.worktrees/` directory (gitignored)
- Adds entries to `.gitignore`

### `wt status`

Show unassigned changes and the status of each worktree.

```bash
wt status
```

Output:
```
  Working in: worktree-staging

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

### `wt switch [branch]`

Switch between branches. If no branch is specified, toggles between `worktree-staging` and `main`.

```bash
# Toggle between worktree-staging and main
wt switch

# Switch to a specific branch
wt switch develop
```

This is a convenient shortcut for `git checkout` with smart defaults:
- If on `worktree-staging`: switches to `main`
- If on any other branch: switches to `worktree-staging`

### `wt create <branch>`

Create a new worktree branching from `worktree-staging`. The branch name is used as the worktree name.

```bash
wt create feature/user-auth    # Creates .worktrees/feature/user-auth/
wt create bugfix/issue-123     # Creates .worktrees/bugfix/issue-123/
```

Arguments:
- `branch`: Branch name (also used as worktree name)

### `wt list`

List all worktrees with their status.

```bash
wt list
```

### `wt assign <worktree> [file|directory|.]`

Assign files to a worktree. Opens fzf for interactive multi-select if no file is specified.

```bash
# Interactive selection with fzf (recommended)
wt assign feature/user-auth

# Or specify files directly:
wt assign feature/user-auth app/models/user.rb    # Single file
wt assign feature/user-auth app/models/           # Directory
wt assign feature/user-auth .                     # All files
```

What happens:
1. Files remain in `worktree-staging` (committed)
2. Changes are copied to the worktree (uncommitted)
3. Files are removed from "unassigned" list

### `wt stage <worktree> <file|directory|.>`

Stage files in a worktree for selective commits.

```bash
wt stage feature/user-auth app/models/user.rb    # Single file
wt stage feature/user-auth app/models/           # Directory
wt stage feature/user-auth .                     # All files
```

Use this when you want to commit only specific files from a worktree.

### `wt unstage <worktree> <file|.>`

Unstage files in a worktree (equivalent to git reset). Removes files from the staging area but keeps the changes as uncommitted.

```bash
wt unstage feature/user-auth app/models/user.rb    # Single file
wt unstage feature/user-auth .                     # All files
```

This is the opposite of `wt stage` - useful when you've staged files but want to unstage them without losing changes.

### `wt commit <worktree> <message>`

Commit changes in a worktree without having to cd into it.

```bash
wt commit feature/user-auth "Add user authentication"
```

The commit command is staging-aware:
- If files are staged (via `wt stage`), commits only those files
- If no files are staged, auto-stages all changes and commits them
- Shows clear messaging about what's being committed

### `wt uncommit <worktree>`

Uncommit the last commit in a worktree (brings changes back to uncommitted).

```bash
wt uncommit feature/user-auth
```

### `wt unassign <worktree> <file|.>`

Unassign file(s) from a worktree - reverts the commit in `worktree-staging` and removes changes from the worktree.

```bash
wt unassign feature/user-auth app/models/user.rb    # Single file
wt unassign feature/user-auth .                     # All assigned files
```

The file(s) will show up as "unassigned" again.

### `wt apply <worktree>`

Apply (cherry-pick) commits from a worktree to worktree-staging. This means that all of the code will be available for further development or testing in worktree-staging.

```bash
wt apply feature-auth
```

### `wt unapply <worktree>`

Unapply (revert) commits that were applied from a worktree. This means that you effectively remove the worktree changeset from the worktree-staging branch and those changes are no longer available for further development or testing in worktree-staging. You can add them back to worktree-staging with `wt apply <worktree>`.

```bash
wt unapply feature-auth
```

### `wt push <worktree>`

Push a worktree's branch to the remote.

```bash
wt push feature-auth
```

### `wt pr <worktree>`

Open the GitHub PR creation page for a worktree's branch in your browser. If the branch hasn't been pushed yet, `wt` will push it automatically.

```bash
wt pr feature-auth
```

This command:
1. Checks if the branch is pushed to origin (pushes if not)
2. Detects the worktree's branch name
3. Constructs the GitHub PR creation URL
4. Opens it in your default browser

Works with both HTTPS and SSH remote URLs.

### `wt sync [branch]`

Sync `worktree-staging` with another branch (default: main). Automatically detects and cleans up worktrees whose branches have been merged.

```bash
wt sync           # Sync from main and clean up merged worktrees
wt sync develop   # Sync from develop
```

What it does:
1. Fetches latest changes from origin
2. Updates local branch from origin
3. Merges branch into `worktree-staging`
4. **Automatically detects worktrees with merged branches**
5. **Removes merged worktrees**
6. **Deletes corresponding remote branches**

This is now a one-stop command for staying in sync and cleaning up finished work.

### `wt remove <worktree> [--force]`

Remove a worktree and clean up metadata.

```bash
wt remove feature-auth
wt remove bugfix --force
```

## Workflow Examples

### Basic Feature Development

```bash
# Start fresh
$ wt init

  ✓ Created .worktree-flow directory
  ✓ Created .worktrees directory
  ✓ Updated .gitignore
  ✓ Created worktree-staging branch
  ✓ Worktree workflow initialized

# Create feature worktree
$ wt create feature/auth

  ✓ Created worktree 'feature/auth' at .worktrees/feature/auth
  ✓ Branched from worktree-staging as feature/auth

# Make changes in worktree-staging
# ... edit files ...

$ wt status

  Working in: worktree-staging

  Unassigned changes:
    M  app/models/user.rb
    A  app/controllers/auth_controller.rb

  Worktrees:
    feature/auth (feature/auth) - 0 uncommitted, 0 commit(s)

# Assign files interactively with fzf
$ wt assign feature/auth

  Select files to assign (TAB to select, ENTER to confirm)...
  # fzf opens, select both files

  ✓ Assigned 2 file(s) to 'feature/auth' and committed to worktree-staging

# Commit in worktree
$ wt commit feature/auth "Add authentication"

  No files staged, auto-staging all changes...
  ✓ Committed changes in 'feature/auth'

# Push and create PR
$ wt push feature/auth

  ✓ Pushed branch 'feature/auth' to origin

$ wt pr feature/auth

  Opening PR creation page for branch 'feature/auth'...
  URL: https://github.com/user/repo/compare/main...feature/auth?expand=1
  ✓ PR page opened for 'feature/auth'

# After PR is merged to main, sync
$ wt sync

  Syncing worktree-staging with 'main'...
  Fetching latest changes from origin...
  Updating local main from origin/main...
  ✓ Successfully synced worktree-staging with 'main'
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
wt create feature/auth
wt create feature/api-refactor

# Make changes
# ... edit multiple files ...

# Assign to different features using fzf
wt assign feature/auth         # Select auth-related files
wt assign feature/api-refactor # Select API files

# Commit separately
wt commit feature/auth "Add authentication"
wt commit feature/api-refactor "Refactor API base"

# Push and create PRs
wt pr feature/auth
wt pr feature/api-refactor
```

### Assigning Directories

```bash
wt create feature/model-refactor

# Make changes to multiple files in app/models/
# ... edit files ...

# Assign entire directory
wt assign feature/model-refactor app/models/

# Commit
wt commit feature/model-refactor "Refactor models"
```

### Selective Staging and Commits

```bash
wt create feature/multi-part

# Assign files interactively
wt assign feature/multi-part

# Stage and commit only specific files
wt stage feature/multi-part app/models/user.rb
wt commit feature/multi-part "Add user model"

# Stage and commit remaining files
wt stage feature/multi-part .
wt commit feature/multi-part "Add controllers and views"
```

Or commit everything at once without staging:
```bash
# If no files are staged, commit auto-stages all changes
wt commit feature/multi-part "Implement complete feature"
```

### Undoing Mistakes

```bash
# Assigned wrong file
wt unassign feature/user-auth app/models/admin.rb

# Committed too early in worktree
wt uncommit feature/user-auth

# Unassign all files from a worktree
wt unassign feature/user-auth .
```

### Syncing After Merges

```bash
# Your feature branches got merged to main on GitHub
# Just run sync - it handles everything automatically

wt sync

# Output:
# ✓ Successfully synced worktree-staging with 'main'
# ✓ Branch 'feature/user-auth' has been merged into main
#   - Removing worktree 'auth'...
#   - Deleting remote branch 'feature/user-auth'...
#   ✓ Cleaned up 'auth'
# ✓ Cleaned up 1 merged worktree(s)

# Done! worktree-staging is updated and merged work is cleaned up
# Continue working on new features
```

## Tips

1. **Always work in `worktree-staging`** - Don't make changes in `main`
2. **Use `wt switch` to quickly toggle** between `worktree-staging` and `main`
3. **Run `wt status` often** to see your abbreviations, worktree state, and uncommitted files
4. **Use directory assignment** for bulk file operations: `wt assign app/models feature-x`
5. **Use selective staging** for multi-part commits: `wt stage <worktree> <file>` then `wt commit`
6. **Skip staging for quick commits** - `wt commit` auto-stages everything if nothing is staged
7. **Sync regularly** after merging features to main: `wt sync`
8. **Use `wt unassign`** to correct assignment mistakes
9. **Commit small, logical changes** in worktrees for clearer history
10. **Use abbreviated commands** for speed: `wt as` (assign), `wt ap` (apply), `wt cr` (create)

## Troubleshooting

### Command not found: wt

Make sure the installation directory is in your PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add this to your `~/.bashrc` or `~/.zshrc`.

### Not on worktree-staging branch

`wt status` will warn you if you're not on `worktree-staging`. Switch back with:

```bash
git checkout worktree-staging
```

### Failed to apply patch

This can happen if files have diverged. Try:
1. Committing changes in the worktree first
2. Using `wt apply` if needed
3. Resolving any conflicts

### Merge conflicts when syncing

When running `wt sync`, you may encounter merge conflicts. Resolve them normally:

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
- Virtual branch concept (worktree-staging)

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

- `bin/wt` - Main dispatcher
- `commands/*.sh` - Subcommand implementations
- `lib/wt-lib.sh` - Shared library functions
- `lib/abbreviations.sh` - Abbreviation generation

## Development

To hack on `wt`:

```bash
cd ~/Code/wt

# Edit files
# ... make changes ...

# Run tests (one command - fast and local)
./run-tests.sh

# Test without installing
./bin/wt status

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
