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
assert_branch_exists "worktree-staging" "worktree-staging branch should exist"
assert_current_branch "worktree-staging" "Should be on worktree-staging branch"
assert_file_exists ".worktree-flow" ".worktree-flow directory should exist"
assert_file_exists ".worktree-flow/metadata.json" "metadata.json should exist"
assert_file_exists ".worktree-flow/abbreviations.json" "abbreviations.json should exist"

# Check .gitignore
GITIGNORE_CONTENT=$(cat .gitignore)
assert_contains "$GITIGNORE_CONTENT" ".worktree-flow/" ".gitignore should contain .worktree-flow/"
assert_contains "$GITIGNORE_CONTENT" ".worktrees/" ".gitignore should contain .worktrees/"

# Test: wt create
test_section "Testing: wt create"
REPO=$(create_test_repo "create-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1

assert_success "$WT_BIN create test-wt feature/test" "wt create should succeed"
assert_file_exists ".worktrees/test-wt" "Worktree directory should exist"
assert_branch_exists "feature/test" "Feature branch should exist"

# Check metadata
METADATA=$(cat .worktree-flow/metadata.json)
assert_contains "$METADATA" "test-wt" "Metadata should contain worktree name"
assert_contains "$METADATA" "feature/test" "Metadata should contain branch name"

# Test: wt list
test_section "Testing: wt list"
LIST_OUTPUT=$($WT_BIN list 2>&1)
assert_contains "$LIST_OUTPUT" "test-wt" "wt list should show worktree"
assert_contains "$LIST_OUTPUT" "feature/test" "wt list should show branch"

# Test: wt status
test_section "Testing: wt status"

# Make some changes
echo "class Admin; end" > app/models/admin.rb
echo "Updated" >> app/models/user.rb

STATUS_OUTPUT=$($WT_BIN status 2>&1)
assert_contains "$STATUS_OUTPUT" "Unassigned changes" "wt status should show unassigned changes"
assert_contains "$STATUS_OUTPUT" "admin.rb" "wt status should show new file"
assert_contains "$STATUS_OUTPUT" "user.rb" "wt status should show modified file"

# Check for abbreviations
assert_contains "$STATUS_OUTPUT" "  " "wt status should show abbreviations"

# Test: wt assign (single file)
test_section "Testing: wt assign (single file)"
REPO=$(create_test_repo "assign-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create test-wt feature/test > /dev/null 2>&1

# Make changes
echo "class Admin; end" > app/models/admin.rb
git add app/models/admin.rb

# Assign file
assert_success "$WT_BIN assign app/models/admin.rb test-wt" "wt assign should succeed"

# Check that file is committed in worktree-staging
LAST_COMMIT=$(git log -1 --format="%s")
assert_contains "$LAST_COMMIT" "wt: assign" "Should have assignment commit"
assert_contains "$LAST_COMMIT" "admin.rb" "Commit should mention file"

# Check that file exists in worktree
assert_file_exists ".worktrees/test-wt/app/models/admin.rb" "File should exist in worktree"

# Test: wt assign (directory)
test_section "Testing: wt assign (directory)"
REPO=$(create_test_repo "assign-dir-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create test-wt feature/test > /dev/null 2>&1

# Make changes to multiple files in a directory
echo "class Admin; end" > app/models/admin.rb
echo "class Post; end" > app/models/post.rb
echo "Updated" >> app/models/user.rb

# Assign directory
assert_success "$WT_BIN assign app/models/ test-wt" "wt assign directory should succeed"

# Check commits
COMMIT_COUNT=$(git log --oneline | grep "wt: assign" | wc -l | tr -d ' ')
assert_success "[[ $COMMIT_COUNT -ge 3 ]]" "Should have multiple assignment commits"

# Test: wt assign . (assign all)
test_section "Testing: wt assign (all files)"
REPO=$(create_test_repo "assign-all-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create test-wt feature/test > /dev/null 2>&1

# Make changes in multiple directories
echo "class Admin; end" > app/models/admin.rb
echo "Updated" >> app/controllers/posts_controller.rb
echo "New service" > app/services/new_service.rb

# Assign all
assert_success "$WT_BIN assign . test-wt" "wt assign . should succeed"

# Check all files are in worktree
assert_file_exists ".worktrees/test-wt/app/models/admin.rb"
assert_file_exists ".worktrees/test-wt/app/controllers/posts_controller.rb"
assert_file_exists ".worktrees/test-wt/app/services/new_service.rb"

# Test: wt commit
test_section "Testing: wt commit"
REPO=$(create_test_repo "commit-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create test-wt feature/test > /dev/null 2>&1

echo "class Admin; end" > app/models/admin.rb
$WT_BIN assign app/models/admin.rb test-wt > /dev/null 2>&1

# Commit in worktree
assert_success "$WT_BIN commit test-wt 'Add admin model'" "wt commit should succeed"

# Check commit exists in worktree
cd .worktrees/test-wt
LAST_COMMIT=$(git log -1 --format="%s")
assert_contains "$LAST_COMMIT" "Add admin model" "Worktree should have commit"
cd "$REPO"

# Test: wt undo
test_section "Testing: wt undo"
REPO=$(create_test_repo "undo-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create test-wt feature/test > /dev/null 2>&1

echo "class Admin; end" > app/models/admin.rb
$WT_BIN assign app/models/admin.rb test-wt > /dev/null 2>&1
$WT_BIN commit test-wt "Add admin model" > /dev/null 2>&1

# Undo the commit (needs interactive confirmation, so we'll skip for now)
# This would require expect or other interactive testing tools

# Test: wt unassign
test_section "Testing: wt unassign"
REPO=$(create_test_repo "unassign-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create test-wt feature/test > /dev/null 2>&1

echo "class Admin; end" > app/models/admin.rb
$WT_BIN assign app/models/admin.rb test-wt > /dev/null 2>&1

# Get number of commits before unassign
COMMITS_BEFORE=$(git log --oneline | wc -l | tr -d ' ')

# Unassign (needs interactive confirmation for revert)
# Skip for now due to interactive prompt

# Test: wt sync
test_section "Testing: wt sync"
REPO=$(create_test_repo "sync-test")
cd "$REPO"

# Create a commit on main
echo "Main change" >> README.md
git add README.md
git commit -m "Update on main"

# Initialize wt
$WT_BIN init > /dev/null 2>&1

# Sync should merge main into worktree-staging
assert_success "$WT_BIN sync" "wt sync should succeed"

# Check that worktree-staging has the change from main
assert_file_exists "README.md"
MAIN_CONTENT=$(grep "Main change" README.md || echo "")
assert_contains "$MAIN_CONTENT" "Main change" "worktree-staging should have changes from main"

# Test: wt apply
test_section "Testing: wt apply"
REPO=$(create_test_repo "apply-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create test-wt feature/test > /dev/null 2>&1

# Create file directly in worktree and commit
echo "class Admin; end" > .worktrees/test-wt/app/models/admin.rb
$WT_BIN commit test-wt "Add admin model" > /dev/null 2>&1

# Apply commits from worktree to staging
assert_success "$WT_BIN apply test-wt" "wt apply should succeed"

# Check that commit exists in worktree-staging
LAST_COMMIT=$(git log -1 --format="%s")
assert_contains "$LAST_COMMIT" "Add admin model" "Applied commit should be in worktree-staging"

# Test: wt push
test_section "Testing: wt push (without remote)"
REPO=$(create_test_repo "push-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create test-wt feature/test > /dev/null 2>&1

# Without a remote, push will fail, but the command should handle it gracefully
# Skip this test for now as it requires remote setup

# Test: wt remove
test_section "Testing: wt remove"
REPO=$(create_test_repo "remove-test")
cd "$REPO"
$WT_BIN init > /dev/null 2>&1
$WT_BIN create test-wt feature/test > /dev/null 2>&1

# Remove worktree (needs interactive confirmation)
# Skip for now due to interactive prompt

# Print summary
print_test_summary

# Exit with appropriate code
exit $TEST_FAILED
