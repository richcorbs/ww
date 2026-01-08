#!/usr/bin/env bash
# Comprehensive test suite for wt

set -e

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-helpers.sh"

# Setup
setup_test_env

# Test: wt init
test_section "Testing: wt init"
REPO=$(create_test_repo "init-test")
cd "$REPO"

assert_success "$WT_BIN init" "wt init should succeed"
assert_branch_exists "wt-working" "wt-working branch should exist"
assert_current_branch "wt-working" "Should be on wt-working branch"

# Check .gitignore
GITIGNORE_CONTENT=$(cat .gitignore)
assert_contains "$GITIGNORE_CONTENT" ".worktrees/" ".gitignore should contain .worktrees/"

# Test: wt create (simplified - branch name only)
test_section "Testing: wt create (simplified)"
REPO=$(create_test_repo "create-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1

assert_success "$WT_BIN create feature/test" "wt create should succeed"
assert_file_exists ".worktrees/feature/test" "Worktree directory should exist at .worktrees/feature/test"
assert_branch_exists "feature/test" "Feature branch should exist"

# Test: wt list
test_section "Testing: wt list"
LIST_OUTPUT=$($WT_BIN list 2>&1)
assert_contains "$LIST_OUTPUT" "feature/test" "wt list should show worktree"

# Test: wt status
test_section "Testing: wt status"

# Make some changes
echo "class Admin; end" > app/models/admin.rb
echo "Updated" >> app/models/user.rb

STATUS_OUTPUT=$($WT_BIN status 2>&1)
assert_contains "$STATUS_OUTPUT" "Unassigned changes" "wt status should show unassigned changes"
assert_contains "$STATUS_OUTPUT" "admin.rb" "wt status should show new file"
assert_contains "$STATUS_OUTPUT" "user.rb" "wt status should show modified file"

# Test: wt assign (single file with new argument order)
test_section "Testing: wt assign (single file, new arg order)"
REPO=$(create_test_repo "assign-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create feature/test > /dev/null 2>&1

# Make changes
echo "class Admin; end" > app/models/admin.rb

# Assign file - new argument order: worktree first, file second
assert_success "$WT_BIN assign feature/test app/models/admin.rb" "wt assign should succeed with new arg order"

# Check that file is committed in wt-working
LAST_COMMIT=$(git log -1 --format="%s")
assert_contains "$LAST_COMMIT" "wt: assign" "Should have assignment commit"
assert_contains "$LAST_COMMIT" "admin.rb" "Commit should mention file"
assert_contains "$LAST_COMMIT" "feature/test" "Commit should mention worktree"

# Check that file exists in worktree
assert_file_exists ".worktrees/feature/test/app/models/admin.rb" "File should exist in worktree"

# Test: wt assign (auto-create worktree)
test_section "Testing: wt assign (auto-create worktree)"
REPO=$(create_test_repo "assign-autocreate-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1

# Make changes
echo "class Admin; end" > app/models/admin.rb

# Assign to non-existent worktree - should auto-create
assert_success "$WT_BIN assign new-feature app/models/admin.rb" "wt assign should auto-create worktree"

# Check that worktree was created
assert_file_exists ".worktrees/new-feature" "Worktree should be auto-created"
assert_branch_exists "new-feature" "Branch should be auto-created"

# Check that file exists in worktree
assert_file_exists ".worktrees/new-feature/app/models/admin.rb" "File should exist in auto-created worktree"

# Test: wt assign (directory)
test_section "Testing: wt assign (directory)"
REPO=$(create_test_repo "assign-dir-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create feature/test > /dev/null 2>&1

# Make changes to multiple files in a directory
echo "class Admin; end" > app/models/admin.rb
echo "class Post; end" > app/models/post.rb
echo "Updated" >> app/models/user.rb

# Assign directory - new argument order
assert_success "$WT_BIN assign feature/test app/models/" "wt assign directory should succeed"

# Check commits
COMMIT_COUNT=$(git log --oneline | grep "wt: assign" | wc -l | tr -d ' ')
assert_success "[[ $COMMIT_COUNT -ge 3 ]]" "Should have multiple assignment commits"

# Test: wt assign . (assign all)
test_section "Testing: wt assign (all files)"
REPO=$(create_test_repo "assign-all-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create feature/test > /dev/null 2>&1

# Make changes in multiple directories
echo "class Admin; end" > app/models/admin.rb
echo "Updated" >> app/controllers/posts_controller.rb
echo "New service" > app/services/new_service.rb

# Assign all - new argument order
assert_success "$WT_BIN assign feature/test ." "wt assign . should succeed"

# Check all files are in worktree
assert_file_exists ".worktrees/feature/test/app/models/admin.rb"
assert_file_exists ".worktrees/feature/test/app/controllers/posts_controller.rb"
assert_file_exists ".worktrees/feature/test/app/services/new_service.rb"

# Test: wt assign (deleted file)
test_section "Testing: wt assign (deleted file)"
REPO=$(create_test_repo "assign-deleted-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create feature/test > /dev/null 2>&1

# Delete an existing file
git rm app/models/user.rb

# Assign the deletion - new argument order
assert_success "$WT_BIN assign feature/test app/models/user.rb" "wt assign should handle deleted files"

# Check that deletion is committed
LAST_COMMIT=$(git log -1 --format="%s")
assert_contains "$LAST_COMMIT" "wt: assign" "Should have assignment commit for deletion"

# Check that file doesn't exist in worktree
assert_file_not_exists ".worktrees/feature/test/app/models/user.rb" "Deleted file should not exist in worktree"

# Test: wt unassign (single file with new argument order)
test_section "Testing: wt unassign (single file, new arg order)"
REPO=$(create_test_repo "unassign-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create feature/test > /dev/null 2>&1

echo "class Admin; end" > app/models/admin.rb
$WT_BIN assign feature/test app/models/admin.rb > /dev/null 2>&1

# Unassign file - new argument order: worktree first, file second
assert_success "$WT_BIN unassign feature/test app/models/admin.rb" "wt unassign should succeed with new arg order"

# Check that file is back in wt-working as uncommitted
STATUS_OUTPUT=$(git status --porcelain)
assert_contains "$STATUS_OUTPUT" "admin.rb" "File should be uncommitted after unassign"

# Test: wt unassign (all files - default behavior)
test_section "Testing: wt unassign (all files)"
REPO=$(create_test_repo "unassign-all-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create feature/test > /dev/null 2>&1

# Assign multiple files
echo "class Admin; end" > app/models/admin.rb
echo "class Post; end" > app/models/post.rb
$WT_BIN assign feature/test app/models/admin.rb > /dev/null 2>&1
$WT_BIN assign feature/test app/models/post.rb > /dev/null 2>&1

# Unassign all (no file argument defaults to all)
assert_success "$WT_BIN unassign feature/test" "wt unassign without file should unassign all"

# Check that files are back as uncommitted
STATUS_OUTPUT=$(git status --porcelain)
assert_contains "$STATUS_OUTPUT" "admin.rb" "admin.rb should be uncommitted"
assert_contains "$STATUS_OUTPUT" "post.rb" "post.rb should be uncommitted"

# Test: wt unassign (with uncommitted changes - should fail gracefully)
test_section "Testing: wt unassign (fail gracefully with uncommitted changes)"
REPO=$(create_test_repo "unassign-fail-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create feature/test > /dev/null 2>&1

# Assign a file
echo "class Admin; end" > app/models/admin.rb
$WT_BIN assign feature/test app/models/admin.rb > /dev/null 2>&1

# Create uncommitted changes (modify existing file to trigger diff-index)
echo "Updated" >> app/models/user.rb

# Try to unassign - should fail because of uncommitted changes
assert_failure "$WT_BIN unassign feature/test app/models/admin.rb" "wt unassign should fail with uncommitted changes"

# Test: wt status (applied indicator)
test_section "Testing: wt status (applied indicator)"
REPO=$(create_test_repo "status-applied-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create feature/test > /dev/null 2>&1

# Assign a file
echo "class Admin; end" > app/models/admin.rb
$WT_BIN assign feature/test app/models/admin.rb > /dev/null 2>&1

# Status should show [applied] because assignment commit is in wt-working
STATUS_OUTPUT=$($WT_BIN status 2>&1)
assert_contains "$STATUS_OUTPUT" "[applied]" "wt status should show [applied] for assigned worktree"

# Test: wt sync
test_section "Testing: wt sync"
REPO=$(create_test_repo "sync-test")
cd "$REPO"

# Create a commit on main
echo "Main change" >> README.md
git add README.md
git commit -m "Update on main" > /dev/null 2>&1

# Initialize wt
$WT_BIN init > /dev/null 2>&1

# Sync should merge main into wt-working
assert_success "$WT_BIN sync" "wt sync should succeed"

# Check that wt-working has the change from main
assert_file_exists "README.md"
MAIN_CONTENT=$(grep "Main change" README.md || echo "")
assert_contains "$MAIN_CONTENT" "Main change" "wt-working should have changes from main"

# Test: wt apply
test_section "Testing: wt apply"
REPO=$(create_test_repo "apply-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create feature/test > /dev/null 2>&1

# Assign a file first
echo "class Admin; end" > app/models/admin.rb
$WT_BIN assign feature/test app/models/admin.rb > /dev/null 2>&1

# Create a commit directly in worktree
cd .worktrees/feature/test
echo "class Post; end" > app/models/post.rb
git add app/models/post.rb
git commit -m "Add post model" > /dev/null 2>&1
cd "$REPO"

# Apply commits from worktree to staging
assert_success "$WT_BIN apply feature/test" "wt apply should succeed"

# Check that commit exists in wt-working
LAST_COMMIT=$(git log -1 --format="%s")
assert_contains "$LAST_COMMIT" "Add post model" "Applied commit should be in wt-working"

# Test: wt unapply
test_section "Testing: wt unapply"
REPO=$(create_test_repo "unapply-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create feature/test > /dev/null 2>&1

# Assign a file
echo "class Admin; end" > app/models/admin.rb
$WT_BIN assign feature/test app/models/admin.rb > /dev/null 2>&1

# Create a new commit directly in the worktree (not via assignment)
cd .worktrees/feature/test
echo "class Post; end" > app/models/post.rb
git add app/models/post.rb
git commit -m "Add post model" > /dev/null 2>&1
cd "$REPO"

# Apply the worktree commit to staging
$WT_BIN apply feature/test > /dev/null 2>&1

# Get commit count before unapply
COMMITS_BEFORE=$(git log --oneline | wc -l | tr -d ' ')

# Unapply
assert_success "$WT_BIN unapply feature/test" "wt unapply should succeed"

# Check that revert commit was created
COMMITS_AFTER=$(git log --oneline | wc -l | tr -d ' ')
assert_success "[[ $COMMITS_AFTER -gt $COMMITS_BEFORE ]]" "Should have revert commit"

# Test: Status display format (YX swap)
test_section "Testing: Status display format (YX swap)"
REPO=$(create_test_repo "status-format-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1

# Create a file with unstaged changes
echo "Updated" >> app/models/user.rb

STATUS_OUTPUT=$($WT_BIN status 2>&1)
# Should show with unstaged status first (M in first position means unstaged modified)
assert_contains "$STATUS_OUTPUT" "user.rb" "wt status should show modified file"

# Stage the file
git add app/models/user.rb

# Make another change (now it's both staged and unstaged)
echo "More updates" >> app/models/user.rb

STATUS_OUTPUT=$($WT_BIN status 2>&1)
# Should show MM (both staged and unstaged)
assert_contains "$STATUS_OUTPUT" "MM" "wt status should show MM for staged and unstaged"

# Test: wt remove
test_section "Testing: wt remove"
REPO=$(create_test_repo "remove-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create feature/test > /dev/null 2>&1

# Note: wt remove requires confirmation, so we can't test it non-interactively
# Just verify the worktree exists
assert_file_exists ".worktrees/feature/test" "Worktree should exist before remove"

# Print summary
print_test_summary

# Exit with appropriate code
exit $TEST_FAILED
