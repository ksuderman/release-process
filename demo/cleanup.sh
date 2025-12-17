#!/bin/bash
# Demo Cleanup Script
# This script removes all test repositories created for the demo.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_step() {
    echo -e "${GREEN}==>${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

# Check prerequisites
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) is required."
    exit 1
fi

# Get GitHub username
GITHUB_USER=$(gh api user --jq '.login')
echo_step "Using GitHub user: ${GITHUB_USER}"

# Repository list
REPOS=("test-helm-chart" "test-helm-deps" "test-ansible-playbook" "test-helm-repo")

echo ""
echo -e "${RED}WARNING: This will permanently delete the following repositories:${NC}"
for repo in "${REPOS[@]}"; do
    echo "  - ${GITHUB_USER}/${repo}"
done
echo ""
read -p "Are you sure? Type 'DELETE' to confirm: " -r
echo
if [[ ! $REPLY == "DELETE" ]]; then
    echo "Aborted."
    exit 0
fi

echo_step "Deleting repositories..."
for repo in "${REPOS[@]}"; do
    if gh repo view "${GITHUB_USER}/${repo}" &> /dev/null; then
        gh repo delete "${GITHUB_USER}/${repo}" --yes
        echo "  Deleted ${repo}"
    else
        echo_warn "${repo} does not exist, skipping"
    fi
done

# Clean up local files
echo_step "Cleaning up local files..."
WORK_DIR="/Users/suderman/Workspaces/JHU/release-demo-setup"

#rm -rf /tmp/release-demo-setup
#rm -rf /tmp/test-helm-chart /tmp/test-helm-deps /tmp/test-ansible-playbook /tmp/test-helm-repo
rm -rf $WORK_DIR

echo ""
echo_step "Cleanup complete!"
