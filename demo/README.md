# Release Process Demo

This directory contains everything needed to demonstrate the release automation workflows.

## Test Repositories

| Repository | Purpose | Simulates | Branches |
|------------|---------|-----------|----------|
| `test-helm-chart` | Main Helm chart | galaxy-helm | master, dev |
| `test-helm-deps` | Dependencies chart | galaxy-helm-deps | master, dev |
| `test-ansible-playbook` | Ansible playbook | galaxy-k8s-boot | master, dev |
| `test-helm-repo` | Helm chart repository | CloudVE/helm-charts | master only |

## Automated Setup (Recommended)

### Prerequisites

1. **GitHub CLI** authenticated: `gh auth login`
2. **Add read:org scope**: `gh auth refresh -s read:org`
3. **Create a GitHub App** (one-time, see Step 1 below)
4. **Create secrets file** with your app credentials (see Step 2 below)

### Step 1: Create a GitHub App (one-time)

1. Go to **Settings → Developer settings → GitHub Apps → New GitHub App**
2. Configure:
   - **Name**: `<your-username>-release-bot` (must be unique across GitHub)
   - **Homepage URL**: Your GitHub profile URL
   - **Webhook**: Uncheck "Active"
   - **Permissions**: Repository → Contents: **Read & Write**, Metadata: **Read-only**
   - **Where can install**: Only on this account
3. Click **Create GitHub App**
4. Note the **App ID** displayed at the top of the app settings page
5. Scroll to **Private keys** section, click **Generate a private key**, save the `.pem` file
6. **Install the App** on your account:
   - In the left sidebar, click **Install App**
   - Click **Install** next to your account
   - Select **All repositories** (the setup script will manage which repos)
   - Click **Install**

### Step 2: Create secrets file

Create `~/.secret/github-demo-release-token.sh`:
```bash
export RELEASE_TOKEN="ghp_your_pat_here"  # PAT with repo scope (for repository_dispatch)
export RELEASE_APP_ID="123456"            # Your GitHub App ID
export RELEASE_APP_PRIVATE_KEY_PATH="/path/to/your-app.private-key.pem"
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."  # Optional: for notifications
```

### Step 3: Run setup script

```bash
cd /path/to/release-process/demo
./setup.sh
```

The script will:
1. Create all 4 test repositories
2. Initialize them with demo files and workflows
3. Create master and dev branches (dev only for non-helm-repo)
4. Add repositories to your GitHub App installation
5. Set up secrets in each repository
6. Create labels
7. Optionally configure branch protection rulesets

### Step 4: Create release environments (manual)

For each repository (except test-helm-repo), create a `release` environment:
1. Go to repository **Settings → Environments → New environment**
2. Name: `release`
3. Add yourself as a required reviewer

---

## Manual Setup (Alternative)

If you prefer manual setup, follow these steps:

### 1. Create a GitHub App for release automation

1. Go to **Settings → Developer settings → GitHub Apps → New GitHub App**
2. Configure:
   - **Name**: `release-bot-demo` (must be unique across GitHub)
   - **Homepage URL**: Your GitHub profile URL
   - **Webhook**: Uncheck "Active"
   - **Permissions**: Repository → Contents: **Read & Write**, Metadata: **Read-only**
   - **Where can install**: Only on this account
3. Click **Create GitHub App**
4. Note the **App ID** displayed at the top of the app settings page
5. Scroll to **Private keys** section, click **Generate a private key**, save the `.pem` file
6. **Install the App** on your test repositories:
   - In the left sidebar, click **Install App**
   - Click **Install** next to your account
   - Select **Only select repositories**
   - Choose: `test-helm-chart`, `test-helm-deps`, `test-ansible-playbook`, `test-helm-repo`
   - Click **Install**

### 6. Configure repository settings

For each repository (except test-helm-repo):

1. **Create labels**: `major`, `minor`, `patch` (done automatically by setup.sh)
2. **Create `release` environment** with yourself as required reviewer

**Add secrets** (choose one approach):

**Option A: Organization secrets (recommended for production)**
If using a GitHub organization:
1. Go to **Organization Settings → Secrets and variables → Actions**
2. Create organization secrets:
   - `RELEASE_APP_ID` - The GitHub App ID
   - `RELEASE_APP_PRIVATE_KEY` - Contents of the `.pem` file
3. Grant access to only the repositories that need release automation

**Option B: Repository secrets (for personal accounts/demo)**
For each repository, add:
- `RELEASE_APP_ID` - The GitHub App ID (a number)
- `RELEASE_APP_PRIVATE_KEY` - Contents of the `.pem` file

> **Security Note**: Option A is preferred as it stores the private key in one place. Option B duplicates the key across repositories, increasing the attack surface.

For cross-repo triggers, the setup.sh script automatically replaces GITHUB_USER with your username.

### 7. Configure repository rulesets (recommended)

```bash
RELEASE_APP_ID=<your-app-id> ./configure-branch-protection.sh
```

This sets up repository rulesets matching Phase 5 of the implementation plan:
- Require PRs before merging
- Require status checks (lint, tests, commit-lint)
- Require conversation resolution
- Prevent force pushes and deletions
- **GitHub App bypass** - allows release automation to push to protected branches

## Directory Contents

```
demo/
├── README.md                        # This file
├── DEMO_SCRIPT.md                   # Step-by-step demo walkthrough
├── setup.sh                         # Automated setup script
├── cleanup.sh                       # Cleanup script
├── configure-branch-protection.sh   # Repository rulesets setup
├── test-helm-chart/                 # Files for test-helm-chart repo
│   └── .github/workflows/
│       ├── test.yaml                # Lint and mock tests
│       ├── commit-lint.yaml         # Conventional commit enforcement
│       ├── pr-validation.yaml       # Release PR validation
│       ├── release.yaml             # Release workflow with Slack notification
│       └── auto-approve.yaml        # /approve command handler
├── test-helm-deps/                  # Files for test-helm-deps repo
│   └── .github/workflows/
│       ├── test.yaml
│       ├── commit-lint.yaml
│       ├── pr-validation.yaml
│       ├── release.yaml             # With Slack notification
│       ├── update-dependencies.yaml # Receives upstream updates
│       └── auto-approve.yaml
├── test-ansible-playbook/           # Files for test-ansible-playbook repo
│   └── .github/workflows/
│       ├── test.yaml
│       ├── commit-lint.yaml
│       ├── pr-validation.yaml
│       ├── release.yaml             # With Slack notification
│       ├── update-dependencies.yaml
│       └── auto-approve.yaml
└── test-helm-repo/                  # Files for test-helm-repo repo (master only)
    ├── index.yaml                   # Helm repository index
    └── .github/workflows/
        └── notify-new-chart.yaml    # Slack notification for new charts
```

## Running the Demo

See [DEMO_SCRIPT.md](./DEMO_SCRIPT.md) for the step-by-step demonstration walkthrough.

## Troubleshooting

### "Resource not accessible by integration" error
The GitHub App token doesn't have the right permissions. Make sure the app has **Contents: Read & Write**.

### "Actor must be part of the ruleset source" error
The GitHub App is not installed on the repository. Re-run `setup.sh` or manually add the repo to the app installation.

### Commit lint fails with "subject may not be empty"
The `peter-evans/create-pull-request` action needs a `commit-message` parameter. This has been fixed in the demo workflows.

### Push rejected (non-fast-forward)
The workflow needs to pull the latest changes before pushing. The release workflows include `git pull origin master` to handle this.

## Features

### Self-Approval with `/approve` Command

For single-user scenarios where you need to approve your own PRs:

1. Comment `/approve` on any pull request
2. If you have write access, the PR will be approved by the GitHub App
3. A thumbs-up reaction confirms the approval

This allows PRs to meet the "required approvals" requirement without needing a second person.

**Note**: Users without write access who try `/approve` will get a thumbs-down reaction and a denial comment.

### Slack Notifications

When `SLACK_WEBHOOK_URL` is configured, notifications are sent for:

- **Releases**: When any repository completes a release, a message is posted with the version, release link, and triggering user
- **New Helm Charts**: When charts are pushed to test-helm-repo, a message lists the new chart names and commit link

To set up Slack notifications:
1. Create a Slack App at https://api.slack.com/apps
2. Add an Incoming Webhook to your workspace
3. Add the webhook URL as `SLACK_WEBHOOK_URL` secret in each repository (or your secrets file for setup.sh)
