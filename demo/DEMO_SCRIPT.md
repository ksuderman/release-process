# Release Process Demo Script

This document provides a step-by-step walkthrough for demonstrating the release automation workflows.

## Prerequisites

Before the demo, ensure:
- [ ] All 4 test repositories are created and initialized
- [ ] GitHub App created with Contents: Read & Write permissions
- [ ] GitHub App installed on all test repositories
- [ ] `RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY` secrets configured in each repo (except test-helm-repo)
- [ ] `release` environment is created with yourself as required reviewer
- [ ] Labels `major`, `minor`, `patch` exist in each repo
- [ ] `GITHUB_USER` is replaced with your username in all workflow files
- [ ] Repository rulesets configured (optional): `RELEASE_APP_ID=<id> ./configure-branch-protection.sh`
- [ ] `SLACK_WEBHOOK_URL` secret configured (optional): for Slack notifications

## Demo Flow Overview

```
┌─────────────────────┐
│  test-helm-chart    │
│  (main chart)       │
└─────────┬───────────┘
          │ triggers
          ▼
┌─────────────────────┐     ┌─────────────────────┐
│ test-ansible-       │◄────│  test-helm-deps     │
│ playbook            │     │  (deps chart)       │
└─────────────────────┘     └─────────────────────┘
          ▲                           │
          └───────────────────────────┘
                    triggers

All Helm charts publish to:
┌─────────────────────┐
│  test-helm-repo     │
└─────────────────────┘
```

---

## Part 1: Show the Starting State (2 min)

### 1.1 Show repository structure

Open each repository in GitHub and show:
- `master` and `dev` branches exist
- Current versions:
  - test-helm-chart: `chart/Chart.yaml` → version: 1.0.0
  - test-helm-deps: `chart/Chart.yaml` → version: 1.0.0
  - test-ansible-playbook: `VERSION` → 1.0.0
  - test-helm-repo: empty `index.yaml`

### 1.2 Show the workflows

Navigate to Actions tab in test-helm-chart and briefly show:
- `test.yaml` - Runs on PRs and pushes
- `pr-validation.yaml` - Validates release PRs
- `release.yaml` - Orchestrates the release

---

## Part 2: Demonstrate PR Validation (3 min)

### 2.1 Create a feature branch and PR (wrong way)

```bash
cd /tmp/test-helm-chart
git checkout dev
git checkout -b feature/demo-change

# Make a small change
echo "# Demo change" >> README.md
git add README.md
git commit -m "docs: add demo note"
git push origin feature/demo-change
```

Create a PR from `feature/demo-change` → `master` (wrong!)

**Show**: PR validation fails because:
1. Source branch is not `dev`
2. No version label

### 2.2 Create correct release PR

```bash
# Merge feature to dev first
gh pr create --base dev --head feature/demo-change --title "docs: add demo note"
gh pr merge --squash
```

Now create the release PR:
```bash
git checkout dev
git pull
gh pr create --base master --head dev --title "Release: Demo changes" --label "patch"
```

**Show**:
- PR validation passes
- Tests run automatically

---

## Part 3: Execute a Release (5 min)

### 3.1 Approve and merge the PR

In GitHub UI:
1. Review the PR
2. Approve it using one of these methods:
   - Standard review: Click "Review" → "Approve" → "Submit review"
   - **Self-approval**: Comment `/approve` on the PR (triggers the auto-approve workflow)
3. Merge it

**Note**: The `/approve` command is useful for single-user scenarios where you need to approve your own PRs.

### 3.2 Watch the release workflow

Navigate to Actions → Release workflow

**Show each job as it runs**:

1. **test** - Runs lint and mock tests
2. **prepare** - Calculates new version (1.0.0 → 1.0.1)
3. **approve-release** - ⏸️ PAUSES for manual approval
   - Click "Review deployments"
   - Select "release" environment
   - Click "Approve and deploy"
4. **release** - Executes the release:
   - Updates Chart.yaml version
   - Packages Helm chart
   - Pushes to test-helm-repo
   - Creates git tag and GitHub release
   - Merges master back to dev
5. **trigger-downstream** - Sends dispatch to test-ansible-playbook
6. **summary** - Shows release summary and sends Slack notification (if configured)

### 3.3 Verify the release

Show in GitHub:
- New tag `v1.0.1` created
- GitHub release with auto-generated notes
- `chart/Chart.yaml` now shows version 1.0.1
- `dev` branch is in sync with `master`

Show in test-helm-repo:
- New file `test-chart-1.0.1.tgz`
- Updated `index.yaml` with new entry
- (If Slack configured) A notification was sent about the new chart

---

## Part 4: Demonstrate Cascade Effect (3 min)

### 4.1 Show the automated PR

Navigate to test-ansible-playbook → Pull Requests

**Show**: An automated PR was created:
- Title: "chore(deps): update test-chart to 1.0.1"
- Updates `roles/demo/defaults/main.yml`
- Labeled as `automated` and `dependency-update`
- Targets the `dev` branch

### 4.2 Explain the flow

1. test-helm-chart release completed
2. `trigger-downstream` job sent `repository_dispatch` event
3. test-ansible-playbook's `update-dependencies.yaml` workflow received it
4. Workflow created a PR with the version update

**Key point**: The dependency update PR goes to `dev`, not `master`. This allows:
- Review of the change
- Testing before release
- Batching multiple dependency updates

---

## Part 5: Manual Trigger Demo (2 min)

### 5.1 Show workflow_dispatch

Navigate to test-helm-chart → Actions → Release

Click "Run workflow":
- Select branch: `master`
- Select version bump: `minor`
- Click "Run workflow"

**Show**: Same release process runs, but:
- No PR required
- Version bumps from 1.0.1 → 1.1.0
- Useful for hotfixes or manual releases

---

## Part 6: Q&A Talking Points

### Why the approval gate?
- Prevents accidental releases
- Allows final human verification
- Can add wait timer for "cooling off" period

### Why merge master back to dev?
- Keeps dev in sync with latest release
- Version file always matches
- No merge conflicts on next release

### Why PRs to dev for dependency updates?
- Allows review and testing
- Can batch multiple updates
- Maintains the dev → master flow

### What about failures?
- If release fails, manual intervention required
- No partial releases (all or nothing)
- Can re-run failed jobs

### How does this scale?
- Same pattern for all 7 real repositories
- Consistent process reduces cognitive load
- Automation handles the cascade

---

## Quick Reference: Key Files Changed

| Repository | File | Change |
|------------|------|--------|
| test-helm-chart | `chart/Chart.yaml` | version bumped |
| test-helm-repo | `index.yaml` | new chart entry |
| test-helm-repo | `test-chart-X.X.X.tgz` | packaged chart |
| test-ansible-playbook | `roles/demo/defaults/main.yml` | version updated (via PR) |

---

## Cleanup After Demo

```bash
# Delete test repositories
export GH_USER="your-username"
for repo in test-helm-chart test-helm-deps test-ansible-playbook test-helm-repo; do
  gh repo delete ${GH_USER}/${repo} --yes
done

# Remove local clones
rm -rf /tmp/test-helm-chart /tmp/test-helm-deps /tmp/test-ansible-playbook /tmp/test-helm-repo
```
