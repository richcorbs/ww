#!/usr/bin/env bash
# Comprehensive test suite for ww

set -e

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-helpers.sh"

# Setup
setup_test_env

# Test: ww init
test_section "Testing: ww init"
REPO=$(create_test_repo "init-test")
cd "$REPO"

assert_success "$WW_BIN init" "ww init should succeed"
assert_branch_exists "ww-working" "ww-working branch should exist"
assert_current_branch "ww-working" "Should be on ww-working branch"

# Check .gitignore
GITIGNORE_CONTENT=$(cat .gitignore)
assert_contains "$GITIGNORE_CONTENT" ".worktrees/" ".gitignore should contain .worktrees/"

# Test: ww create (simplified - branch name only)
test_section "Testing: ww create (simplified)"
REPO=$(create_test_repo "create-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1

assert_success "$WW_BIN create feature/test" "ww create should succeed"
assert_file_exists ".worktrees/feature/test" "Worktree directory should exist at .worktrees/feature/test"
assert_branch_exists "feature/test" "Feature branch should exist"

# Test: ww list
test_section "Testing: ww list"
LIST_OUTPUT=$($WW_BIN list 2>&1)
assert_contains "$LIST_OUTPUT" "feature/test" "ww list should show worktree"

# Test: ww status
test_section "Testing: ww status"

# Make some changes
echo "class Admin; end" > app/models/admin.rb
echo "Updated" >> app/models/user.rb

STATUS_OUTPUT=$($WW_BIN status 2>&1)
assert_contains "$STATUS_OUTPUT" "Unassigned changes" "ww status should show unassigned changes"
assert_contains "$STATUS_OUTPUT" "admin.rb" "ww status should show new file"
assert_contains "$STATUS_OUTPUT" "user.rb" "ww status should show modified file"

# Test: ww assign (single file with new argument order)
test_section "Testing: ww assign (single file, new arg order)"
REPO=$(create_test_repo "assign-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create feature/test > /dev/null 2>&1

# Make changes
echo "class Admin; end" > app/models/admin.rb

# Assign file - new argument order: worktree first, file second
assert_success "$WW_BIN assign feature/test app/models/admin.rb" "ww assign should succeed with new arg order"

# Check that file is committed in ww-working
LAST_COMMIT=$(git log -1 --format="%s")
assert_contains "$LAST_COMMIT" "ww: assign" "Should have assignment commit"
assert_contains "$LAST_COMMIT" "admin.rb" "Commit should mention file"
assert_contains "$LAST_COMMIT" "feature/test" "Commit should mention worktree"

# Check that file exists in worktree
assert_file_exists ".worktrees/feature/test/app/models/admin.rb" "File should exist in worktree"

# Test: ww assign (auto-create worktree)
test_section "Testing: ww assign (auto-create worktree)"
REPO=$(create_test_repo "assign-autocreate-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1

# Make changes
echo "class Admin; end" > app/models/admin.rb

# Assign to non-existent worktree - should auto-create
assert_success "$WW_BIN assign new-feature app/models/admin.rb" "ww assign should auto-create worktree"

# Check that worktree was created
assert_file_exists ".worktrees/new-feature" "Worktree should be auto-created"
assert_branch_exists "new-feature" "Branch should be auto-created"

# Check that file exists in worktree
assert_file_exists ".worktrees/new-feature/app/models/admin.rb" "File should exist in auto-created worktree"

# Test: ww assign (directory)
test_section "Testing: ww assign (directory)"
REPO=$(create_test_repo "assign-dir-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create feature/test > /dev/null 2>&1

# Make changes to multiple files in a directory
echo "class Admin; end" > app/models/admin.rb
echo "class Post; end" > app/models/post.rb
echo "Updated" >> app/models/user.rb

# Assign directory - new argument order
assert_success "$WW_BIN assign feature/test app/models/" "ww assign directory should succeed"

# Check commits
COMMIT_COUNT=$(git log --oneline | grep "ww: assign" | wc -l | tr -d ' ')
assert_success "[[ $COMMIT_COUNT -ge 3 ]]" "Should have multiple assignment commits"

# Test: ww assign . (assign all)
test_section "Testing: ww assign (all files)"
REPO=$(create_test_repo "assign-all-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create feature/test > /dev/null 2>&1

# Make changes in multiple directories
echo "class Admin; end" > app/models/admin.rb
echo "Updated" >> app/controllers/posts_controller.rb
echo "New service" > app/services/new_service.rb

# Assign all - new argument order
assert_success "$WW_BIN assign feature/test ." "ww assign . should succeed"

# Check all files are in worktree
assert_file_exists ".worktrees/feature/test/app/models/admin.rb"
assert_file_exists ".worktrees/feature/test/app/controllers/posts_controller.rb"
assert_file_exists ".worktrees/feature/test/app/services/new_service.rb"

# Test: ww assign (deleted file)
test_section "Testing: ww assign (deleted file)"
REPO=$(create_test_repo "assign-deleted-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create feature/test > /dev/null 2>&1

# Delete an existing file
git rm app/models/user.rb

# Assign the deletion - new argument order
assert_success "$WW_BIN assign feature/test app/models/user.rb" "ww assign should handle deleted files"

# Check that deletion is committed
LAST_COMMIT=$(git log -1 --format="%s")
assert_contains "$LAST_COMMIT" "ww: assign" "Should have assignment commit for deletion"

# Check that file doesn't exist in worktree
assert_file_not_exists ".worktrees/feature/test/app/models/user.rb" "Deleted file should not exist in worktree"

# Test: ww unassign (single file with new argument order)
test_section "Testing: ww unassign (single file, new arg order)"
REPO=$(create_test_repo "unassign-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create feature/test > /dev/null 2>&1

echo "class Admin; end" > app/models/admin.rb
$WW_BIN assign feature/test app/models/admin.rb > /dev/null 2>&1

# Unassign file - new argument order: worktree first, file second
assert_success "$WW_BIN unassign feature/test app/models/admin.rb" "ww unassign should succeed with new arg order"

# Check that file is back in ww-working as uncommitted
STATUS_OUTPUT=$(git status --porcelain)
assert_contains "$STATUS_OUTPUT" "admin.rb" "File should be uncommitted after unassign"

# Test: ww unassign (all files - default behavior)
test_section "Testing: ww unassign (all files)"
REPO=$(create_test_repo "unassign-all-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create feature/test > /dev/null 2>&1

# Assign multiple files
echo "class Admin; end" > app/models/admin.rb
echo "class Post; end" > app/models/post.rb
$WW_BIN assign feature/test app/models/admin.rb > /dev/null 2>&1
$WW_BIN assign feature/test app/models/post.rb > /dev/null 2>&1

# Unassign all (no file argument defaults to all)
assert_success "$WW_BIN unassign feature/test" "ww unassign without file should unassign all"

# Check that files are back as uncommitted
STATUS_OUTPUT=$(git status --porcelain)
assert_contains "$STATUS_OUTPUT" "admin.rb" "admin.rb should be uncommitted"
assert_contains "$STATUS_OUTPUT" "post.rb" "post.rb should be uncommitted"

# Test: ww unassign (with uncommitted changes - should fail gracefully)
test_section "Testing: ww unassign (fail gracefully with uncommitted changes)"
REPO=$(create_test_repo "unassign-fail-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create feature/test > /dev/null 2>&1

# Assign a file
echo "class Admin; end" > app/models/admin.rb
$WW_BIN assign feature/test app/models/admin.rb > /dev/null 2>&1

# Create uncommitted changes (modify existing file to trigger diff-index)
echo "Updated" >> app/models/user.rb

# Try to unassign - should fail because of uncommitted changes
assert_failure "$WW_BIN unassign feature/test app/models/admin.rb" "ww unassign should fail with uncommitted changes"

# Test: ww status (applied indicator)
test_section "Testing: ww status (applied indicator)"
REPO=$(create_test_repo "status-applied-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create feature/test > /dev/null 2>&1

# Assign a file
echo "class Admin; end" > app/models/admin.rb
$WW_BIN assign feature/test app/models/admin.rb > /dev/null 2>&1

# Status should show [applied] because assignment commit is in ww-working
STATUS_OUTPUT=$($WW_BIN status 2>&1)
assert_contains "$STATUS_OUTPUT" "[applied]" "ww status should show [applied] for assigned worktree"

# Test: ww update
test_section "Testing: ww update"
REPO=$(create_test_repo "update-test")
cd "$REPO"

# Create a commit on main
echo "Main change" >> README.md
git add README.md
git commit -m "Update on main" > /dev/null 2>&1

# Initialize ww
$WW_BIN init > /dev/null 2>&1

# Update should merge main into ww-working
assert_success "$WW_BIN update" "ww update should succeed"

# Check that ww-working has the change from main
assert_file_exists "README.md"
MAIN_CONTENT=$(grep "Main change" README.md || echo "")
assert_contains "$MAIN_CONTENT" "Main change" "ww-working should have changes from main"

# Test: ww apply
test_section "Testing: ww apply"
REPO=$(create_test_repo "apply-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create feature/test > /dev/null 2>&1

# Assign a file first
echo "class Admin; end" > app/models/admin.rb
$WW_BIN assign feature/test app/models/admin.rb > /dev/null 2>&1

# Create a commit directly in worktree
cd .worktrees/feature/test
echo "class Post; end" > app/models/post.rb
git add app/models/post.rb
git commit -m "Add post model" > /dev/null 2>&1
cd "$REPO"

# Apply commits from worktree to staging
assert_success "$WW_BIN apply feature/test" "ww apply should succeed"

# Check that commit exists in ww-working
LAST_COMMIT=$(git log -1 --format="%s")
assert_contains "$LAST_COMMIT" "Add post model" "Applied commit should be in ww-working"

# Test: ww unapply
test_section "Testing: ww unapply"
REPO=$(create_test_repo "unapply-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create feature/test > /dev/null 2>&1

# Assign a file
echo "class Admin; end" > app/models/admin.rb
$WW_BIN assign feature/test app/models/admin.rb > /dev/null 2>&1

# Create a new commit directly in the worktree (not via assignment)
cd .worktrees/feature/test
echo "class Post; end" > app/models/post.rb
git add app/models/post.rb
git commit -m "Add post model" > /dev/null 2>&1
cd "$REPO"

# Apply the worktree commit to staging
$WW_BIN apply feature/test > /dev/null 2>&1

# Get commit count before unapply
COMMITS_BEFORE=$(git log --oneline | wc -l | tr -d ' ')

# Unapply
assert_success "$WW_BIN unapply feature/test" "ww unapply should succeed"

# Check that revert commit was created
COMMITS_AFTER=$(git log --oneline | wc -l | tr -d ' ')
assert_success "[[ $COMMITS_AFTER -gt $COMMITS_BEFORE ]]" "Should have revert commit"

# Test: Status display format (YX swap)
test_section "Testing: Status display format (YX swap)"
REPO=$(create_test_repo "status-format-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1

# Create a file with unstaged changes
echo "Updated" >> app/models/user.rb

STATUS_OUTPUT=$($WW_BIN status 2>&1)
# Should show with unstaged status first (M in first position means unstaged modified)
assert_contains "$STATUS_OUTPUT" "user.rb" "ww status should show modified file"

# Stage the file
git add app/models/user.rb

# Make another change (now it's both staged and unstaged)
echo "More updates" >> app/models/user.rb

STATUS_OUTPUT=$($WW_BIN status 2>&1)
# Should show MM (both staged and unstaged)
assert_contains "$STATUS_OUTPUT" "MM" "ww status should show MM for staged and unstaged"

# Test: ww remove
test_section "Testing: ww remove"
REPO=$(create_test_repo "remove-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create feature/test > /dev/null 2>&1

# Note: ww remove requires confirmation, so we can't test it non-interactively
# Just verify the worktree exists
assert_file_exists ".worktrees/feature/test" "Worktree should exist before remove"

# Print summary
print_test_summary

# Exit with appropriate code
exit $TEST_FAILED
