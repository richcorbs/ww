# Development Guide for ww

This document describes the architecture, design decisions, and development workflow for the ww (worktree workflow manager) project.

## Architecture Overview

### Core Concept

`ww` is a bash-based CLI tool that provides a GitButler-like workflow using native git worktrees. The key innovation is the `ww-working` branch, which serves as a safe staging area isolated from `main`.

### Workflow Flow

1. User works in `ww-working` branch
2. Files are assigned to worktrees (committed to `ww-working`, copied to worktree)
3. Changes are committed in worktrees on their feature branches
4. Feature branches are pushed and merged to `main` via PRs
5. `ww-working` is synced with `main` to get latest changes

## Project Structure

```
~/Code/ww/
├── bin/
│   └── ww                      # Main dispatcher with command routing
├── commands/
│   ├── init.sh                 # Initialize workflow
│   ├── status.sh               # Show status with abbreviations
│   ├── create.sh               # Create worktrees
│   ├── assign.sh               # Assign files (commits to staging)
│   ├── assign-all.sh           # Assign all files
│   ├── commit.sh               # Commit in worktree
│   ├── undo.sh                 # Undo last commit in worktree
│   ├── unassign.sh             # Revert file assignment
│   ├── apply.sh                # Cherry-pick from worktree to staging
│   ├── unapply.sh              # Revert applied commits
│   ├── push.sh                 # Push worktree branch
│   ├── pr.sh                   # Open GitHub PR page
│   ├── update.sh               # Update staging with main
│   ├── list.sh                 # List worktrees
│   └── remove.sh               # Remove worktree
├── lib/
│   ├── ww-lib.sh              # Shared utility functions
│   └── abbreviations.sh        # Two-letter abbreviation system
├── tests/
│   ├── test-helpers.sh         # Test utilities
│   └── test-all.sh             # Comprehensive test suite
├── README.md                   # User documentation
├── DEVELOPMENT.md              # This file
├── install.sh                  # Installation script
└── run-tests.sh                # Test runner

Per-repository metadata (gitignored):
.worktree-flow/
├── metadata.json               # Worktree and commit tracking
└── abbreviations.json          # File-to-abbreviation cache

.worktrees/                     # Worktree directories (gitignored)
└── <worktree-name>/
```

## Key Components

### 1. Main Dispatcher (`bin/ww`)

**Responsibilities:**
- Parse command-line arguments
- Route to appropriate command script
- Support abbreviated commands (e.g., `ww as` → `ww assign`)

**Abbreviated Command Logic:**
- Exact match takes precedence
- If no exact match, find commands starting with the abbreviation
- If exactly one match, use it
- If multiple matches, show "ambiguous command" error

### 2. Command Scripts (`commands/*.sh`)

**Convention:**
- Each command is a separate `.sh` file
- Must define a `cmd_<command_name>` function
- Source `ww-lib.sh` and `abbreviations.sh` automatically via dispatcher
- Should include `show_help()` function for `--help`

**Template for new commands:**
```bash
#!/usr/bin/env bash
# Description of command

show_help() {
  cat <<EOF
Usage: ww <command> <args>

Description of what this command does.

Arguments:
  arg1    Description

Options:
  -h, --help    Show this help message
EOF
}

cmd_<command_name>() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        # Handle arguments
        ;;
    esac
    shift
  done

  # Ensure initialized
  ensure_git_repo
  ensure_initialized

  # Command implementation
}
```

### 3. Shared Library (`lib/ww-lib.sh`)

**Key Functions:**
- `ensure_git_repo()` - Verify we're in a git repo
- `ensure_initialized()` - Verify ww is initialized
- `get_repo_root()` - Get repository root path
- `read_metadata()` / `write_metadata()` - JSON metadata operations
- `worktree_exists()` - Check if worktree exists
- `add_worktree_metadata()` - Track new worktree
- `error()` / `warn()` / `info()` / `success()` - Colored output

**Error Handling:**
- Use `error()` for fatal errors (exits with code 1)
- Use `warn()` for warnings (continues execution)
- Use `info()` for informational messages
- Use `success()` for success messages

### 4. Abbreviation System (`lib/abbreviations.sh`)

**How It Works:**
1. Hash file path to generate initial two-letter code (aa-zz)
2. Check for collisions
3. If collision, increment to next available code
4. Cache in `.worktree-flow/abbreviations.json`
5. Clear cache when files are assigned/committed

**Key Functions:**
- `generate_abbreviation()` - Create abbreviation for file
- `get_abbreviation()` - Retrieve cached abbreviation
- `get_filepath_from_abbrev()` - Reverse lookup
- `set_abbreviation()` / `remove_abbreviation()` - Cache management

### 5. Metadata Storage

**Format (`.worktree-flow/metadata.json`):**
```json
{
  "worktrees": {
    "worktree-name": {
      "branch": "feature/branch-name",
      "path": ".worktrees/worktree-name",
      "created": "2026-01-07T10:30:00Z"
    }
  },
  "applied_commits": {
    "worktree-commit-sha": {
      "worktree": "worktree-name",
      "staging_commit": "staging-commit-sha",
      "applied_at": "2026-01-07T11:00:00Z"
    }
  }
}
```

**Purpose:**
- Track worktrees and their branches
- Track commit relationships (for apply/unapply)
- Enable metadata queries without parsing git directly

## Design Decisions

### 1. Why `ww-working` Branch?

**Problem:** Working directly in `main` is risky - experimental work can pollute the main branch.

**Solution:** Dedicated `ww-working` branch provides:
- Safe experimentation without affecting `main`
- Clear separation between "staging work" and "production code"
- Ability to reset/rebase staging without affecting `main`
- Explicit update step (`ww update`) to pull changes from `main`

### 2. Why Commit on Assign?

**Problem:** Original plan was to just copy files to worktrees without committing.

**Issue:** This caused inconsistency - files would be "unassigned" but also in worktrees.

**Solution:** Commit to `ww-working` when assigning:
- Files are removed from "unassigned" list
- Changes are tracked in git history
- Can be reverted with `ww unassign`
- Worktree gets clean copy to work with

### 3. Why Two-Letter Abbreviations?

**Problem:** Typing full paths is tedious.

**Solution:** GitButler-style abbreviations:
- Fast to type (`ww assign ab feature-x`)
- Deterministic (same file = same abbreviation)
- Collision handling ensures uniqueness
- Cached for consistency

### 4. Why Separate `.worktrees/` Directory?

**Problem:** Originally used `../worktrees/` outside project.

**Issue:** Scattered worktrees, harder to find, not self-contained.

**Solution:** `.worktrees/` inside project:
- Self-contained project structure
- Easy to find and navigate
- Gitignored, so not tracked
- Clean `git clean -fdx` removes everything

### 5. Why Bash Instead of [Language]?

**Rationale:**
- Bash is universal on Unix systems
- Direct git integration without dependencies
- Fast startup time
- Easy to debug and modify
- No compilation step

## Adding New Commands

1. **Create command script:**
   ```bash
   touch commands/newcommand.sh
   chmod +x commands/newcommand.sh
   ```

2. **Implement using template** (see section 2 above)

3. **Add to dispatcher help** (`bin/ww` - `show_usage()`)

4. **Write tests** (`tests/test-all.sh`)

5. **Update README** with command documentation

6. **Test:**
   ```bash
   ./bin/ww newcommand --help
   ./run-tests.sh
   ```

## Testing

### Test Structure

- **test-helpers.sh**: Assertion functions and test utilities
- **test-all.sh**: Comprehensive tests for all commands

### Running Tests

```bash
# Run all tests
./run-tests.sh

# Run specific test (edit test-all.sh to comment out other tests)
./tests/test-all.sh
```

### Writing Tests

```bash
test_section "Testing: my command"
REPO=$(create_test_repo "test-name")
cd "$REPO"

# Setup
$WW_BIN init > /dev/null 2>&1

# Test
assert_success "$WW_BIN newcommand arg" "Should succeed"
assert_file_exists ".some-file" "File should exist"
assert_contains "$(cat .some-file)" "expected" "Should contain text"
```

### Test Helpers

- `assert_success` - Command should succeed
- `assert_failure` - Command should fail
- `assert_file_exists` - File/dir should exist
- `assert_file_not_exists` - File/dir should not exist
- `assert_contains` - String contains substring
- `assert_branch_exists` - Git branch exists
- `assert_current_branch` - Current branch matches expected

## Development Workflow

### Making Changes

1. **Create feature branch:**
   ```bash
   git checkout -b feature/my-change
   ```

2. **Make changes** to code

3. **Test changes:**
   ```bash
   ./run-tests.sh
   ```

4. **Update README** if user-facing changes

5. **Commit:**
   ```bash
   git add -A
   git commit -m "Description of change"
   ```

### Release Process

1. Update version in README (if applicable)
2. Test thoroughly
3. Commit and tag:
   ```bash
   git tag v1.0.0
   git push origin main --tags
   ```

## Common Patterns

### Interactive Confirmations

For destructive operations:
```bash
read -rp "Are you sure? (y/N) " response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
  info "Operation cancelled"
  exit 0
fi
```

### Working with Worktrees

```bash
# Get worktree path
local worktree_path
worktree_path=$(get_worktree_path "$worktree_name")

local repo_root
repo_root=$(get_repo_root)

local abs_path="${repo_root}/${worktree_path}"

# Enter worktree
if pushd "$abs_path" > /dev/null 2>&1; then
  # Do work in worktree
  git commit -m "message"
  popd > /dev/null 2>&1
else
  error "Failed to enter worktree"
fi
```

### Metadata Operations

```bash
# Read
local metadata
metadata=$(read_metadata)

# Query
local branch
branch=$(echo "$metadata" | jq -r '.worktrees["name"].branch')

# Update
metadata=$(echo "$metadata" | jq --arg name "value" '.field = $name')
write_metadata "$metadata"
```

## Debugging

### Enable Bash Debugging

```bash
bash -x ./bin/ww status
```

### Check Metadata

```bash
cat .worktree-flow/metadata.json | jq .
cat .worktree-flow/abbreviations.json | jq .
```

### Git Worktree State

```bash
git worktree list
git log --all --graph --oneline
```

## Future Enhancements

Potential improvements:
- Hunk-level assignment (like GitButler)
- Interactive file selection with fzf
- TUI interface
- Auto-sync on certain events
- Worktree templates
- Stash management between worktrees
- GitHub CLI integration for PR operations
- Conflict resolution helpers

## Troubleshooting Development Issues

### Tests Failing

1. Check test repo isolation - each test should use a fresh repo
2. Verify git config in test repos (user.name, user.email)
3. Check for leftover test repos: `rm -rf test-repos/`

### Command Not Working

1. Check if command script is executable: `chmod +x commands/command.sh`
2. Verify function name matches: `cmd_command_name`
3. Check if command is in dispatcher help

### Metadata Issues

1. Verify JSON is valid: `jq . .worktree-flow/metadata.json`
2. Check write permissions on `.worktree-flow/`
3. Delete and reinitialize: `rm -rf .worktree-flow && ww init`

## Contributing

1. Follow existing code style (bash best practices)
2. Add tests for new features
3. Update documentation (README.md, this file)
4. Use descriptive commit messages
5. Test on macOS, Linux if possible

## Resources

- [Git Worktree Documentation](https://git-scm.com/docs/git-worktree)
- [Bash Style Guide](https://google.github.io/styleguide/shellguide.html)
- [jq Manual](https://stedolan.github.io/jq/manual/)
- [GitButler (inspiration)](https://gitbutler.com/)
