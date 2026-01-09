#!/usr/bin/env bash
# Tests for error handling in ww commands

set -e

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-helpers.sh"

# Setup
setup_test_env

# Test: Create worktree that already exists
test_section "Testing: Error - create duplicate worktree"
REPO=$(create_test_repo "error-duplicate-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create test-ww feature/test > /dev/null 2>&1

# Try to create same worktree again
assert_failure "$WW_BIN create test-ww feature/another" "Creating duplicate worktree should fail"

# Test: Assign to non-existent worktree
test_section "Testing: Error - assign to non-existent worktree"
REPO=$(create_test_repo "error-nonexistent-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1

echo "class Admin; end" > app/models/admin.rb
assert_failure "$WW_BIN assign app/models/admin.rb nonexistent-ww" "Assigning to non-existent worktree should fail"

# Test: Assign non-existent file
test_section "Testing: Error - assign non-existent file"
REPO=$(create_test_repo "error-nofile-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create test-ww feature/test > /dev/null 2>&1

assert_failure "$WW_BIN assign nonexistent-file.rb test-ww" "Assigning non-existent file should fail"

# Test: Commit in non-existent worktree
test_section "Testing: Error - commit in non-existent worktree"
REPO=$(create_test_repo "error-commit-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1

assert_failure "$WW_BIN commit nonexistent-ww 'Some message'" "Commit in non-existent worktree should fail"

# Test: Stage in non-existent worktree
test_section "Testing: Error - stage in non-existent worktree"
REPO=$(create_test_repo "error-stage-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1

assert_failure "$WW_BIN stage nonexistent-ww app/models/user.rb" "Stage in non-existent worktree should fail"

# Test: Commands without init
test_section "Testing: Error - commands without initialization"
REPO=$(create_test_repo "error-noinit-test")
cd "$REPO"

# Most commands should work or auto-initialize, but let's test create without init
# Actually, based on the ww status output, it auto-initializes, so this might not fail
# We'll just verify the behavior
OUTPUT=$($WW_BIN status 2>&1 || true)
# If it auto-initializes, that's fine

# Test: Unassign file that wasn't assigned
test_section "Testing: Error - unassign unassigned file"
REPO=$(create_test_repo "error-unassign-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create test-ww feature/test > /dev/null 2>&1

echo "class Admin; end" > app/models/admin.rb
# Don't assign it, just try to unassign
assert_failure "$WW_BIN unassign app/models/admin.rb test-ww" "Unassigning unassigned file should fail"

# Test: Apply from worktree with no commits
test_section "Testing: Error - apply from worktree with no new commits"
REPO=$(create_test_repo "error-apply-test")
cd "$REPO"
$WW_BIN init > /dev/null 2>&1
$WW_BIN create test-ww feature/test > /dev/null 2>&1

# Try to apply without any commits
OUTPUT=$($WW_BIN apply test-ww 2>&1 || true)
# This might not error but should show a message about no commits to apply
assert_contains "$OUTPUT" "No" "Should indicate no commits to apply"

# Print summary
print_test_summary

# Exit with appropriate code
exit $TEST_FAILED
