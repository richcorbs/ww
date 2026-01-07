# wt - Worktree Workflow Manager

A GitButler-inspired workflow using native git worktrees, allowing you to work on multiple features simultaneously while keeping changes organized in a dedicated staging branch.

## Features

- **Dedicated staging branch**: All work happens in `worktree-staging`, keeping `main` clean
- **File-level assignment**: Selectively assign files to different worktrees using two-letter abbreviations
- **Directory assignment**: Assign all changed files in a directory at once
- **Automatic commits**: Files are committed to `worktree-staging` when assigned
- **Commit tracking**: Track which commits have been applied between branches
- **Safe operations**: Work in isolation without affecting your main branch
- **Simple CLI**: Single `wt` command with intuitive subcommands

## Installation

### Requirements

- Git 2.5 or higher
- jq (JSON processor)
- Bash 4+

### Install

```bash
cd ~/Code/wt
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

# 3. Check status (see two-letter abbreviations)
wt status
# Output:
#   Unassigned changes:
#     ab  app/models/user.rb
#     cd  app/controllers/sessions_controller.rb

# 4. Create a worktree for a feature
wt create feature-auth feature/user-auth

# 5. Assign files to the worktree (commits to worktree-staging automatically)
wt assign ab feature-auth
wt assign cd feature-auth

# 6. Commit changes in the worktree
wt commit feature-auth "Add user authentication"

# 7. Push the feature branch
wt push feature-auth

# 8. When done, merge feature branch to main via PR
# Then sync worktree-staging with main
wt sync
```

## How It Works

### The worktree-staging Branch

Instead of working directly in `main`, all your work happens in a dedicated `worktree-staging` branch:

1. **Initialize**: `wt init` creates/checks out `worktree-staging`
2. **Work**: Make all changes in `worktree-staging`
3. **Assign**: Files are committed to `worktree-staging` when assigned to worktrees
4. **Worktrees**: Branch off from `worktree-staging` (not main)
5. **Merge**: When features are done, merge to `main` via normal git/PR
6. **Sync**: Use `wt sync` to merge `main` back into `worktree-staging`

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
- Creates/checks out `worktree-staging` branch
- Creates `.worktree-flow/` directory for metadata
- Creates `.worktrees/` directory (gitignored)
- Adds entries to `.gitignore`

### `wt status`

Show uncommitted changes with abbreviations and worktree status.

```bash
wt status
```

Output:
```
Unassigned changes:
  ab  M  app/models/user.rb
  cd  A  app/controllers/sessions_controller.rb
  ef  ?? config/routes.rb

Worktrees:
  feature-auth (feature/user-auth) - 2 uncommitted, 1 commit(s)
  bugfix-login (bugfix/login-issue) - 0 uncommitted, 0 commit(s)
```

### `wt create <name> <branch> [path]`

Create a new worktree branching from `worktree-staging`.

```bash
wt create feature-auth feature/user-auth
wt create bugfix bugfix/issue-123 ~/my-worktrees/bugfix
```

Arguments:
- `name`: Identifier for the worktree
- `branch`: Branch name for the worktree
- `path`: Optional custom path (default: `.worktrees/<name>`)

### `wt list`

List all worktrees with their status.

```bash
wt list
```

### `wt assign <file|abbreviation|directory> <worktree>`

Assign files to a worktree and commit them to `worktree-staging`.

```bash
# Single file by abbreviation
wt assign ab feature-auth

# Single file by path
wt assign app/models/user.rb feature-auth

# All changed files in a directory
wt assign app/models/ feature-auth
```

The files are:
1. Committed to `worktree-staging`
2. Copied as uncommitted changes to the worktree
3. Removed from "unassigned" list

### `wt assign-all <worktree>`

Assign all uncommitted changes to a worktree.

```bash
wt assign-all feature-auth
```

### `wt commit <worktree> <message>`

Commit changes in a worktree without having to cd into it.

```bash
wt commit feature-auth "Add user authentication"
```

### `wt undo <worktree>`

Undo the last commit in a worktree (brings changes back to uncommitted).

```bash
wt undo feature-auth
```

### `wt unassign <file|abbreviation> <worktree>`

Unassign a file from a worktree - reverts the commit in `worktree-staging` and removes changes from the worktree.

```bash
wt unassign ab feature-auth
wt unassign app/models/user.rb feature-auth
```

The file will show up as "unassigned" again.

### `wt apply <worktree>`

Apply (cherry-pick) commits from a worktree to `worktree-staging`.

```bash
wt apply feature-auth
```

This cherry-picks all new commits from the worktree branch that aren't in `worktree-staging` yet.

### `wt unapply <worktree>`

Unapply (revert) commits that were applied from a worktree.

```bash
wt unapply feature-auth
```

Uses `git revert` to safely undo changes.

### `wt push <worktree>`

Push a worktree's branch to the remote.

```bash
wt push feature-auth
```

### `wt sync [branch]`

Sync `worktree-staging` with another branch (default: main).

```bash
wt sync           # Sync from main
wt sync develop   # Sync from develop
```

Use this after your feature branches are merged to main, to keep `worktree-staging` up-to-date.

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
wt init

# Create feature worktree
wt create auth feature/auth

# Make changes in worktree-staging
# ... edit files ...

wt status
# Output: ab app/models/user.rb, cd app/controllers/auth_controller.rb

# Assign files (commits to worktree-staging)
wt assign ab auth
wt assign cd auth

# Commit in worktree
wt commit auth "Add authentication"

# Push and create PR
wt push auth

# After PR is merged to main, sync
wt sync
```

### Working on Multiple Features

```bash
wt create auth feature/auth
wt create api feature/api-refactor

# Make changes
# ... edit multiple files ...

wt status
# Output:
#   ab app/models/user.rb
#   cd app/controllers/api/base_controller.rb
#   ef app/services/auth_service.rb

# Assign to different features
wt assign ab auth
wt assign ef auth
wt assign cd api

# Commit separately
wt commit auth "Add authentication"
wt commit api "Refactor API base"

# Push both
wt push auth
wt push api
```

### Assigning Directories

```bash
wt create refactor feature/model-refactor

# Make changes to multiple files in app/models/
# ... edit files ...

# Assign entire directory
wt assign app/models/ refactor

# Commit
wt commit refactor "Refactor models"
```

### Undoing Mistakes

```bash
# Assigned wrong file
wt unassign ab feature-auth

# Committed too early in worktree
wt undo feature-auth

# Made a mistake in assignment, uncommit and reassign
wt unassign app/models/user.rb feature-auth
# ... make corrections ...
wt assign app/models/user.rb feature-auth
```

### Syncing After Merges

```bash
# Your feature branches got merged to main
# Sync worktree-staging to get those changes

wt sync

# Now worktree-staging has everything from main
# Continue working on new features
```

## Tips

1. **Always work in `worktree-staging`** - Don't make changes in `main`
2. **Run `wt status` often** to see your abbreviations and worktree state
3. **Use directory assignment** for bulk file operations: `wt assign app/models/ feature-x`
4. **Sync regularly** after merging features to main: `wt sync`
5. **Use `wt unassign`** to correct assignment mistakes
6. **Commit small, logical changes** in worktrees for clearer history

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

# Test without installing
./bin/wt status

# When ready, run install
./install.sh
```
