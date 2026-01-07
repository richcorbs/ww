#!/usr/bin/env bash
# Test helper functions for wt test suite

# Colors for test output
readonly TEST_RED='\033[0;31m'
readonly TEST_GREEN='\033[0;32m'
readonly TEST_YELLOW='\033[1;33m'
readonly TEST_BLUE='\033[0;34m'
readonly TEST_NC='\033[0m'

# Test counters
TEST_COUNT=0
TEST_PASSED=0
TEST_FAILED=0

# Get the root directory of the wt project
WT_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WT_BIN="${WT_PROJECT_ROOT}/bin/wt"

# Test repository paths
TEST_REPOS_DIR="${WT_PROJECT_ROOT}/test-repos"

# Setup test environment
setup_test_env() {
  # Clean up any existing test repos
  rm -rf "$TEST_REPOS_DIR"
  mkdir -p "$TEST_REPOS_DIR"
}

# Create a fresh test repository
create_test_repo() {
  local repo_name="${1:-test-repo}"
  local repo_path="${TEST_REPOS_DIR}/${repo_name}"

  # Remove if exists
  rm -rf "$repo_path"

  # Create directory
  mkdir -p "$repo_path"

  # Initialize git
  cd "$repo_path" || return 1
  git init
  git config user.name "Test User"
  git config user.email "test@example.com"

  # Create initial commit
  echo "# Test Repository" > README.md
  mkdir -p app/models app/controllers app/services
  echo "class User; end" > app/models/user.rb
  echo "class PostsController; end" > app/controllers/posts_controller.rb
  echo "class AuthService; end" > app/services/auth_service.rb

  git add -A
  git commit -m "Initial commit"

  echo "$repo_path"
}

# Assert command succeeds
assert_success() {
  local command="$1"
  local description="${2:-$command}"

  ((TEST_COUNT++))

  if eval "$command" > /dev/null 2>&1; then
    ((TEST_PASSED++))
    echo -e "${TEST_GREEN}✓${TEST_NC} $description"
    return 0
  else
    ((TEST_FAILED++))
    echo -e "${TEST_RED}✗${TEST_NC} $description"
    echo -e "  ${TEST_YELLOW}Command failed: $command${TEST_NC}"
    return 1
  fi
}

# Assert command fails
assert_failure() {
  local command="$1"
  local description="${2:-$command}"

  ((TEST_COUNT++))

  if eval "$command" > /dev/null 2>&1; then
    ((TEST_FAILED++))
    echo -e "${TEST_RED}✗${TEST_NC} $description"
    echo -e "  ${TEST_YELLOW}Command should have failed but succeeded: $command${TEST_NC}"
    return 1
  else
    ((TEST_PASSED++))
    echo -e "${TEST_GREEN}✓${TEST_NC} $description"
    return 0
  fi
}

# Assert file exists
assert_file_exists() {
  local file_path="$1"
  local description="${2:-File $file_path should exist}"

  ((TEST_COUNT++))

  if [[ -f "$file_path" ]] || [[ -d "$file_path" ]]; then
    ((TEST_PASSED++))
    echo -e "${TEST_GREEN}✓${TEST_NC} $description"
    return 0
  else
    ((TEST_FAILED++))
    echo -e "${TEST_RED}✗${TEST_NC} $description"
    echo -e "  ${TEST_YELLOW}File/directory does not exist: $file_path${TEST_NC}"
    return 1
  fi
}

# Assert file does not exist
assert_file_not_exists() {
  local file_path="$1"
  local description="${2:-File $file_path should not exist}"

  ((TEST_COUNT++))

  if [[ ! -f "$file_path" ]] && [[ ! -d "$file_path" ]]; then
    ((TEST_PASSED++))
    echo -e "${TEST_GREEN}✓${TEST_NC} $description"
    return 0
  else
    ((TEST_FAILED++))
    echo -e "${TEST_RED}✗${TEST_NC} $description"
    echo -e "  ${TEST_YELLOW}File/directory exists but shouldn't: $file_path${TEST_NC}"
    return 1
  fi
}

# Assert string contains substring
assert_contains() {
  local string="$1"
  local substring="$2"
  local description="${3:-String should contain '$substring'}"

  ((TEST_COUNT++))

  if [[ "$string" == *"$substring"* ]]; then
    ((TEST_PASSED++))
    echo -e "${TEST_GREEN}✓${TEST_NC} $description"
    return 0
  else
    ((TEST_FAILED++))
    echo -e "${TEST_RED}✗${TEST_NC} $description"
    echo -e "  ${TEST_YELLOW}Expected substring not found${TEST_NC}"
    echo -e "  String: $string"
    echo -e "  Substring: $substring"
    return 1
  fi
}

# Assert git branch exists
assert_branch_exists() {
  local branch_name="$1"
  local description="${2:-Branch $branch_name should exist}"

  ((TEST_COUNT++))

  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    ((TEST_PASSED++))
    echo -e "${TEST_GREEN}✓${TEST_NC} $description"
    return 0
  else
    ((TEST_FAILED++))
    echo -e "${TEST_RED}✗${TEST_NC} $description"
    return 1
  fi
}

# Assert current branch
assert_current_branch() {
  local expected_branch="$1"
  local description="${2:-Current branch should be $expected_branch}"

  ((TEST_COUNT++))

  local current_branch
  current_branch=$(git branch --show-current)

  if [[ "$current_branch" == "$expected_branch" ]]; then
    ((TEST_PASSED++))
    echo -e "${TEST_GREEN}✓${TEST_NC} $description"
    return 0
  else
    ((TEST_FAILED++))
    echo -e "${TEST_RED}✗${TEST_NC} $description"
    echo -e "  ${TEST_YELLOW}Expected: $expected_branch, Got: $current_branch${TEST_NC}"
    return 1
  fi
}

# Print test summary
print_test_summary() {
  echo ""
  echo "========================================="
  if [[ $TEST_FAILED -eq 0 ]]; then
    echo -e "${TEST_GREEN}All tests passed!${TEST_NC}"
  else
    echo -e "${TEST_RED}Some tests failed${TEST_NC}"
  fi
  echo "Total: $TEST_COUNT"
  echo -e "Passed: ${TEST_GREEN}$TEST_PASSED${TEST_NC}"
  echo -e "Failed: ${TEST_RED}$TEST_FAILED${TEST_NC}"
  echo "========================================="

  return $TEST_FAILED
}

# Test section header
test_section() {
  echo ""
  echo -e "${TEST_BLUE}========================================="
  echo -e "$1"
  echo -e "=========================================${TEST_NC}"
  echo ""
}
