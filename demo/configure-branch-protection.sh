#!/bin/bash
# Configure Branch Protection using Repository Rulesets
#
# This script sets up repository rulesets with a GitHub App bypass for releases.
# Rulesets are more flexible than classic branch protection and allow apps to
# bypass rules while still enforcing them for all users (including admins).
#
# Prerequisites:
# - GitHub CLI (gh) installed and authenticated
# - Repositories already created via setup.sh
# - A GitHub App created and installed (for bypass)
#
# Environment variables:
#   RELEASE_APP_ID - The GitHub App ID to add to bypass list (optional)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

RELEASE_APP_ID=2461902

echo_step() {
    echo -e "${GREEN}==>${NC} $1"
}

echo_info() {
    echo -e "${BLUE}   ${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

echo_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

# Check prerequisites
if ! command -v gh &> /dev/null; then
    echo_error "GitHub CLI (gh) is required. Install it from https://cli.github.com/"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo_error "Please authenticate with GitHub CLI: gh auth login"
    exit 1
fi

# Get GitHub username
GITHUB_USER=$(gh api user --jq '.login')
echo_step "Using GitHub user: ${GITHUB_USER}"

# Check for GitHub App ID
# Repository admins can bypass via PR only (can merge without checks/approvals, but must use PR)
ADMIN_BYPASS="{\"actor_id\": 5, \"actor_type\": \"RepositoryRole\", \"bypass_mode\": \"pull_request\"}"

if [ -z "${RELEASE_APP_ID}" ]; then
    echo_warn "RELEASE_APP_ID not set. Rulesets will be created without a GitHub App bypass."
    echo_warn "To add a GitHub App bypass, set RELEASE_APP_ID and re-run this script."
    echo ""
    # Only admin bypass (via PR)
    BYPASS_ACTORS="[${ADMIN_BYPASS}]"
else
    echo_step "Using GitHub App ID: ${RELEASE_APP_ID} for bypass"
    # Bypass actors:
    # - GitHub App: bypass_mode=always (needed for automated version bumps and direct pushes)
    # - Admins: bypass_mode=pull_request (can merge PRs without checks, but cannot push directly)
    BYPASS_ACTORS="[{\"actor_id\": ${RELEASE_APP_ID}, \"actor_type\": \"Integration\", \"bypass_mode\": \"always\"}, ${ADMIN_BYPASS}]"
fi

# Demo repositories (exclude test-helm-repo as it doesn't need protection)
REPOS=(
    "test-helm-chart"
    "test-helm-deps"
    "test-ansible-playbook"
)

echo ""
echo "This script will configure repository rulesets for:"
for repo in "${REPOS[@]}"; do
    echo "  - ${GITHUB_USER}/${repo}"
done
echo ""
echo "Rulesets to be created:"
echo ""
echo "  1. 'Protect master' ruleset:"
echo "     - Target: master branch"
echo "     - Require PR before merging"
echo "     - Require 1 approval"
echo "     - Dismiss stale reviews on new commits"
echo "     - Require status checks to pass (strict)"
echo "     - Block force pushes and deletions"
if [ -n "${RELEASE_APP_ID}" ]; then
echo "     - Bypass: GitHub App (ID: ${RELEASE_APP_ID})"
fi
echo ""
echo "  2. 'Protect dev' ruleset:"
echo "     - Target: dev branch"
echo "     - Require PR before merging"
echo "     - Require 1 approval"
echo "     - Require status checks to pass (non-strict)"
echo "     - Block force pushes and deletions"
if [ -n "${RELEASE_APP_ID}" ]; then
echo "     - Bypass: GitHub App (ID: ${RELEASE_APP_ID})"
fi
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Function to delete existing rulesets
delete_existing_rulesets() {
    local repo=$1

    echo_info "Checking for existing rulesets..."
    local rulesets
    rulesets=$(gh api "repos/${GITHUB_USER}/${repo}/rulesets" --jq '.[].id' 2>/dev/null || echo "")

    for ruleset_id in $rulesets; do
        echo_info "Deleting existing ruleset ${ruleset_id}..."
        gh api -X DELETE "repos/${GITHUB_USER}/${repo}/rulesets/${ruleset_id}" 2>/dev/null || true
    done
}

# Function to create a ruleset
create_ruleset() {
    local repo=$1
    local name=$2
    local branch=$3
    local strict=$4
    local checks=$5
    local dismiss_stale=$6

    echo_info "Creating ruleset '${name}'..."

    # Build status checks array (integration_id is optional, omit if not needed)
    local status_checks=""
    for check in $(echo "$checks" | jq -r '.[]'); do
        if [ -n "$status_checks" ]; then
            status_checks="${status_checks},"
        fi
        status_checks="${status_checks}{\"context\": \"${check}\"}"
    done

    local response
    response=$(gh api -X POST "repos/${GITHUB_USER}/${repo}/rulesets" \
        --input - 2>&1 <<EOF
{
    "name": "${name}",
    "target": "branch",
    "enforcement": "active",
    "bypass_actors": ${BYPASS_ACTORS},
    "conditions": {
        "ref_name": {
            "include": ["refs/heads/${branch}"],
            "exclude": []
        }
    },
    "rules": [
        {
            "type": "pull_request",
            "parameters": {
                "required_approving_review_count": 1,
                "dismiss_stale_reviews_on_push": ${dismiss_stale},
                "require_code_owner_review": false,
                "require_last_push_approval": false,
                "required_review_thread_resolution": false
            }
        },
        {
            "type": "required_status_checks",
            "parameters": {
                "strict_required_status_checks_policy": ${strict},
                "required_status_checks": [${status_checks}]
            }
        },
        {
            "type": "non_fast_forward"
        }
    ]
}
EOF
) || {
        echo_warn "Failed to create ruleset '${name}' for ${repo}"
        echo_warn "Response: ${response}"
        return 1
    }

    echo_info "  ✓ Ruleset '${name}' created"
}

# Configure each repository
for repo in "${REPOS[@]}"; do
    echo ""
    echo_step "Configuring ${repo}..."

    # Check if repo exists
    if ! gh repo view "${GITHUB_USER}/${repo}" &> /dev/null; then
        echo_warn "Repository ${repo} does not exist, skipping"
        continue
    fi

    # Delete existing rulesets to start fresh
    delete_existing_rulesets "${repo}"

    # Master branch ruleset (stricter)
    create_ruleset \
        "${repo}" \
        "Protect master" \
        "master" \
        "true" \
        '["lint-pr-title", "lint-commits", "lint", "mock-test", "validate-release-pr"]' \
        "true"

    # Dev branch ruleset (less strict)
    create_ruleset \
        "${repo}" \
        "Protect dev" \
        "dev" \
        "false" \
        '["lint-pr-title", "lint-commits", "lint", "mock-test"]' \
        "false"

    echo_info "✓ ${repo} configured"
done

echo ""
echo_step "Ruleset configuration complete!"
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo ""
if [ -z "${RELEASE_APP_ID}" ]; then
echo "1. NO BYPASS CONFIGURED - The release workflow will fail to push directly."
echo "   To fix this:"
echo "   a. Create a GitHub App at: https://github.com/settings/apps/new"
echo "   b. Install it on your repositories"
echo "   c. Re-run: RELEASE_APP_ID=<app-id> ./configure-branch-protection.sh"
echo ""
fi
echo "2. Status checks must run at least once for GitHub to recognize them."
echo "   Create a test PR to trigger the workflows first."
echo ""
echo "3. To view rulesets in the UI:"
for repo in "${REPOS[@]}"; do
    echo "   https://github.com/${GITHUB_USER}/${repo}/settings/rules"
done
echo ""
echo "4. To delete all rulesets (for cleanup):"
echo "   for id in \$(gh api repos/${GITHUB_USER}/REPO/rulesets --jq '.[].id'); do"
echo "     gh api -X DELETE repos/${GITHUB_USER}/REPO/rulesets/\$id"
echo "   done"
echo ""
