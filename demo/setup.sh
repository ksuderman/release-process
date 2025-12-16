#!/bin/bash
# Demo Setup Script
# This script creates and initializes all test repositories for the release process demo.

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

# Confirm before proceeding
echo ""
echo "This script will:"
echo "  1. Create 4 test repositories under ${GITHUB_USER}"
echo "  2. Initialize them with demo files and workflows"
echo "  3. Create master and dev branches"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="/Users/suderman/Workspaces/JHU/release-demo-setup"
source ~/.secret/github-demo-release-token.sh
source ~/.secret/slack-app.sh

# Clean up any previous setup
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Repository list
REPOS=("test-helm-chart" "test-helm-deps" "test-ansible-playbook" "test-helm-repo")

# Create repositories
echo_step "Creating repositories..."
for repo in "${REPOS[@]}"; do
    echo_step "Checking $repo"
    if gh repo view "${GITHUB_USER}/${repo}" &> /dev/null; then
        echo_warn "Repository ${repo} already exists, skipping creation"
    else
        gh repo create "${repo}" --public -d "Demo: Release process test repository"
        echo "  Created ${repo}"
    fi
done

# Clone and initialize each repository
echo_step "Initializing repositories..."
for repo in "${REPOS[@]}"; do
    echo "  Setting up ${repo}..."

    # Clone
    gh repo clone "${GITHUB_USER}/${repo}" "${WORK_DIR}/${repo}"
    cd "${WORK_DIR}/${repo}"

    # Copy files from demo directory
    cp -r "${SCRIPT_DIR}/${repo}/." .

    # Replace GITHUB_USER placeholder in workflow files
    if [ -d ".github/workflows" ]; then
        find .github/workflows -name "*.yaml" -exec sed -i.bak "s/GITHUB_USER/${GITHUB_USER}/g" {} \;
        find .github/workflows -name "*.bak" -delete
    fi

    # Replace GITHUB_USER in README
    if [ -f "README.md" ]; then
        sed -i.bak "s/GITHUB_USER/${GITHUB_USER}/g" README.md
        rm -f README.md.bak
    fi

    # Create .gitignore
    echo ".DS_Store" > .gitignore

    # Commit and push to master
    git add -A
    git commit -m "Initial commit" || true
    git push origin master || git push origin main

    # Rename main to master if needed
    DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
    if [ "${DEFAULT_BRANCH}" == "main" ]; then
        git branch -m main master
        git push origin master
        git push origin --delete main || true
    fi

    # Create dev branch and secrets (except for test-helm-repo which only needs master)
    if [ "${repo}" != "test-helm-repo" ]; then
        git checkout -b dev
        git push origin dev
        gh repo edit "${GITHUB_USER}/${repo}" --default-branch dev
    fi
    gh secret set RELEASE_TOKEN --body $RELEASE_TOKEN
    gh secret set RELEASE_APP_ID --body $RELEASE_APP_ID
    gh secret set RELEASE_APP_PRIVATE_KEY < $RELEASE_APP_PRIVATE_KEY_PATH
    if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        gh secret set SLACK_WEBHOOK_URL --body $SLACK_WEBHOOK_URL
    fi
    cd "${WORK_DIR}"
done

# Create labels in each repository (except test-helm-repo)
echo_step "Creating labels..."
for repo in "test-helm-chart" "test-helm-deps" "test-ansible-playbook"; do
    echo "  Adding labels to ${repo}..."
    gh label create "major" --repo "${GITHUB_USER}/${repo}" --color "d73a4a" --description "Major version bump" 2>/dev/null || true
    gh label create "minor" --repo "${GITHUB_USER}/${repo}" --color "0e8a16" --description "Minor version bump" 2>/dev/null || true
    gh label create "patch" --repo "${GITHUB_USER}/${repo}" --color "1d76db" --description "Patch version bump" 2>/dev/null || true
    gh label create "automated" --repo "${GITHUB_USER}/${repo}" --color "ededed" --description "Automated PR" 2>/dev/null || true
    gh label create "dependency-update" --repo "${GITHUB_USER}/${repo}" --color "0366d6" --description "Dependency update" 2>/dev/null || true
done

# Add repositories to GitHub App installation
echo_step "Adding repositories to GitHub App installation..."
if [ -n "${RELEASE_APP_ID}" ]; then
    # Get the installation ID for the app on the user's account
    INSTALLATION_ID=$(gh api /user/installations --jq ".installations[] | select(.app_id == ${RELEASE_APP_ID}) | .id" 2>&1) || true

    if [ -z "${INSTALLATION_ID}" ] || [[ "${INSTALLATION_ID}" == *"error"* ]] || [[ "${INSTALLATION_ID}" == *"{"* ]]; then
        echo_warn "GitHub App (ID: ${RELEASE_APP_ID}) is not installed on your account or API call failed."
        echo_warn "Please install it first at: https://github.com/settings/apps"
        echo_warn "Response was: ${INSTALLATION_ID}"
    else
        echo "  Found installation ID: ${INSTALLATION_ID}"
        for repo in "${REPOS[@]}"; do
            REPO_ID=$(gh api "/repos/${GITHUB_USER}/${repo}" --jq '.id' 2>&1) || true
            if [ -n "${REPO_ID}" ] && [[ "${REPO_ID}" =~ ^[0-9]+$ ]]; then
                echo "  Adding ${repo} (ID: ${REPO_ID}) to app installation..."
                RESULT=$(gh api -X PUT "/user/installations/${INSTALLATION_ID}/repositories/${REPO_ID}" 2>&1) || true
                if [ -z "${RESULT}" ] || [[ "${RESULT}" == *"null"* ]] || [[ "${RESULT}" == "{}" ]]; then
                    echo "    ✓ Added ${repo}"
                else
                    echo "    ✗ Failed to add ${repo}: ${RESULT}"
                fi
            else
                echo_warn "Could not get repo ID for ${repo}: ${REPO_ID}"
            fi
        done
    fi
else
    echo_warn "RELEASE_APP_ID not set, skipping GitHub App installation setup"
fi

echo ""
echo_step "Setup complete!"
echo ""
echo "Next steps:"
echo ""
echo "1. Create a Personal Access Token (PAT) with 'repo' and 'workflow' scopes:"
echo "   https://github.com/settings/tokens/new"
echo ""
echo "2. Add the PAT as a secret named 'RELEASE_TOKEN' in each repository:"
for repo in "test-helm-chart" "test-helm-deps" "test-ansible-playbook"; do
    echo "   https://github.com/${GITHUB_USER}/${repo}/settings/secrets/actions/new"
done
echo ""
echo "3. Create a 'release' environment with yourself as required reviewer:"
for repo in "test-helm-chart" "test-helm-deps" "test-ansible-playbook"; do
    echo "   https://github.com/${GITHUB_USER}/${repo}/settings/environments/new"
done
echo ""
echo "4. Review the demo script: ${SCRIPT_DIR}/DEMO_SCRIPT.md"
echo ""
echo "Repository URLs:"
for repo in "${REPOS[@]}"; do
    echo "  https://github.com/${GITHUB_USER}/${repo}"
done
echo ""

# Offer to configure branch protection
read -p "Would you like to configure branch protection rulesets? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    "${SCRIPT_DIR}/configure-branch-protection.sh"
fi
