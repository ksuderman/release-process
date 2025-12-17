# Release Automation Implementation Plan

**Status**: PENDING REVIEW
**Last Updated**: 2025-12-12
**Next Step**: Send plan out for team review before implementation begins

### Recent Changes (2025-12-12)
- **Phase 1.1**: Replaced PAT (`RELEASE_TOKEN`) with GitHub App authentication for better security and ruleset bypass support
- **Phase 5**: Replaced classic branch protection with Repository Rulesets (allows GitHub App bypass while enforcing rules for all users)
- **Release Workflow**: Added fixes discovered during demo testing:
  - Added `ref: master` to checkout to get merge commit
  - Added `git pull origin master` before version bump to prevent push rejection
  - Added git config for external repo clones (helm-charts)

> **Note**: The release workflow example in Phase 2.3 (galaxy-helm) demonstrates the complete GitHub App pattern. All other repository workflows (Phases 3, 4, 4a, 4b, 4c) should follow the same pattern, replacing `secrets.RELEASE_TOKEN` with the GitHub App token generation step using `actions/create-github-app-token@v1`.

---

## Current State Analysis

### Existing Infrastructure

| Repository | Workflows | Version Location | Notes |
|------------|-----------|-----------------|-------|
| galaxy-helm | `test.yaml`, ~~`packaging.yml`~~ | `galaxy/Chart.yaml` | `packaging.yml` is deprecated, do not use |
| galaxy-helm-deps | None | `galaxy-deps/Chart.yaml` | Needs all workflows |
| galaxy-k8s-boot | None | `VERSION` file | Needs all workflows |
| galaxykubeman-helm | `lint.yaml`, ~~`packaging.yml`~~ | `galaxykubeman/Chart.yaml` | `packaging.yml` uses deprecated `cloudve/helm-ci` |
| galaxy-cvmfs-csi-helm | ~~`packaging.yml`~~ | `galaxy-cvmfs-csi/Chart.yaml` | `packaging.yml` uses deprecated `cloudve/helm-ci` |
| galaxy-docker-k8s | None | Tags only (e.g., `v4.2.0`) | Ansible playbook; triggers Galaxy repo PR on release |
| CloudVE/helm-charts | N/A | N/A | Helm chart repository (destination) |

### Deprecated Components (DO NOT USE)

- **`packaging.yml`** in galaxy-helm - Being deprecated
- **`cloudve/helm-ci@master`** action - Being deprecated; tries to do too many things

### Key Files to Update on Release

**galaxy-k8s-boot** (updated by upstream releases):
- `bin/launch_vm.sh`: `GALAXY_CHART_VERSION` and `GALAXY_DEPS_VERSION`
- `roles/galaxy_k8s_deployment/defaults/main.yml`: `galaxy_chart_version` and `galaxy_deps_version`

**galaxy (upstream)** (updated by galaxy-docker-k8s releases):
- `.k8s_ci.Dockerfile`: `GALAXY_PLAYBOOK_BRANCH` ARG (e.g., `v4.2.0`)

**galaxy-helm-deps** (updated by galaxy-cvmfs-csi-helm releases):
- `galaxy-deps/Chart.yaml`: `galaxy-cvmfs-csi` dependency version

---

## Implementation Plan

### Phase 1: Prerequisites and Shared Components

#### 1.1 Create GitHub App for Release Automation

**Action Required**: Create a GitHub App instead of a PAT for better security and to enable bypassing branch protection rulesets.

**Create the GitHub App** (Settings → Developer settings → GitHub Apps → New GitHub App):

| Setting | Value |
|---------|-------|
| **Name** | `galaxy-release-bot` (or similar unique name) |
| **Homepage URL** | `https://github.com/galaxyproject` |
| **Webhook** | Uncheck "Active" (not needed) |
| **Permissions** | Repository → Contents: **Read & Write** |
| | Repository → Metadata: **Read-only** |
| | Repository → Pull requests: **Read & Write** |
| **Where can install** | Only on this account |

After creating:
1. Note the **App ID** (shown at top of app settings page)
2. Generate a **Private Key** (scroll to "Private keys" section)
3. **Install the App** on all repositories in the release ecosystem

Store as secrets in each repository:
- `RELEASE_APP_ID` - The App ID (a number)
- `RELEASE_APP_PRIVATE_KEY` - Contents of the downloaded `.pem` file

**Why GitHub App instead of PAT?**
- Apps can be added to Repository Ruleset bypass lists, allowing automated releases to push to protected branches
- App tokens are scoped per-repository and expire quickly
- No need to manage personal token expiration
- Better audit trail of automated actions

#### 1.2 Configure Slack Webhook

**Action Required**: Create a Slack incoming webhook for the `#galaxy-k8s-sig` channel on `galaxy.slack.com`.

Store as `SLACK_WEBHOOK_URL` in each repository's secrets.

#### 1.3 Configure GitHub Environments

Create a `release` environment in each repository with:
- **Required reviewers**: Repository owners/maintainers
- **Wait timer**: Optional (e.g., 5 minutes to allow cancellation)

This enables manual approval before releases proceed.

#### 1.4 Configure Dependabot

Create `.github/dependabot.yml` in each repository to automatically update dependencies.

**File**: `.github/dependabot.yml` (all repositories)

```yaml
version: 2
updates:
  # GitHub Actions
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 5
    labels:
      - "dependencies"
      - "github-actions"
    commit-message:
      prefix: "ci"
```

**Additional for galaxy-helm**: `.github/dependabot.yml`

```yaml
version: 2
updates:
  # GitHub Actions
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 5
    labels:
      - "dependencies"
      - "github-actions"
    commit-message:
      prefix: "ci"

  # Helm dependencies (custom ecosystem not natively supported)
  # Note: Dependabot doesn't natively support Helm Chart.yaml dependencies.
  # Use the helm-dependencies workflow below instead.
```

**File**: `.github/workflows/check-helm-deps.yaml` (galaxy-helm and galaxy-helm-deps)

```yaml
name: Check Helm Dependencies
on:
  schedule:
    - cron: '0 9 * * 1'  # Every Monday at 9am UTC
  workflow_dispatch: {}

jobs:
  check-deps:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Helm
        run: curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

      - name: Install yq
        run: |
          sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq

      - name: Check for dependency updates
        id: check
        run: |
          CHART_PATH="${{ github.repository == 'galaxyproject/galaxy-helm' && 'galaxy' || 'galaxy-deps' }}"
          UPDATES=""

          # Extract dependencies from Chart.yaml
          deps=$(yq e '.dependencies[] | .name + ":" + .repository + ":" + .version' ${CHART_PATH}/Chart.yaml 2>/dev/null || echo "")

          for dep in $deps; do
            NAME=$(echo $dep | cut -d: -f1)
            REPO=$(echo $dep | cut -d: -f2-)
            REPO=${REPO%:*}
            CURRENT=$(echo $dep | rev | cut -d: -f1 | rev)

            # Add repo and get latest version
            helm repo add temp-$NAME $REPO 2>/dev/null || continue
            LATEST=$(helm search repo temp-$NAME/$NAME --versions -o json | jq -r '.[0].version' 2>/dev/null || echo "")

            if [ -n "$LATEST" ] && [ "$CURRENT" != "$LATEST" ]; then
              UPDATES="${UPDATES}\n- $NAME: $CURRENT -> $LATEST"
            fi
          done

          if [ -n "$UPDATES" ]; then
            echo "updates_found=true" >> $GITHUB_OUTPUT
            echo -e "Updates available:$UPDATES"
          else
            echo "updates_found=false" >> $GITHUB_OUTPUT
            echo "All dependencies are up to date"
          fi

      - name: Create issue for updates
        if: steps.check.outputs.updates_found == 'true'
        uses: peter-evans/create-issue-from-file@v5
        with:
          title: "Helm dependency updates available"
          content-filepath: /dev/stdin
          labels: dependencies,helm
```

---

### Phase 2: galaxy-helm New Release Workflow

**Note**: The existing `packaging.yml` is deprecated and will not be modified. Create new workflows from scratch.

#### 2.1 Create Commit-Lint Workflow

**File**: `.github/workflows/commit-lint.yaml` (all repositories)

This workflow enforces [Conventional Commits](https://www.conventionalcommits.org/) format for PR titles, which are used for squash-merged commits.

```yaml
name: Commit Lint
on:
  pull_request:
    types: [opened, edited, synchronize, reopened]

jobs:
  lint-pr-title:
    runs-on: ubuntu-latest
    steps:
      - name: Validate PR title follows Conventional Commits
        uses: amannn/action-semantic-pull-request@v5
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          # Configure allowed types
          types: |
            feat
            fix
            docs
            style
            refactor
            perf
            test
            build
            ci
            chore
            revert
          # Configure allowed scopes (optional)
          scopes: |
            helm
            deps
            k8s
            ansible
            gcp
            ci
            release
          # Require scope to be provided
          requireScope: false
          # Disable validation for WIP PRs
          ignoreLabels: |
            work-in-progress
            wip
          # Custom error message
          subjectPattern: ^(?![A-Z]).+$
          subjectPatternError: |
            The subject "{subject}" found in the pull request title "{title}"
            must not start with an uppercase character.

  lint-commits:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install commitlint
        run: npm install -g @commitlint/cli @commitlint/config-conventional

      - name: Create commitlint config
        run: |
          cat > commitlint.config.js << 'EOF'
          module.exports = {
            extends: ['@commitlint/config-conventional'],
            rules: {
              'type-enum': [2, 'always', [
                'feat', 'fix', 'docs', 'style', 'refactor',
                'perf', 'test', 'build', 'ci', 'chore', 'revert'
              ]],
              'scope-enum': [1, 'always', [
                'helm', 'deps', 'k8s', 'ansible', 'gcp', 'ci', 'release'
              ]],
              'subject-case': [2, 'never', ['start-case', 'pascal-case', 'upper-case']],
              'header-max-length': [2, 'always', 100]
            }
          };
          EOF

      - name: Lint commits
        run: |
          # Lint all commits in the PR
          npx commitlint --from ${{ github.event.pull_request.base.sha }} --to ${{ github.event.pull_request.head.sha }} --verbose
```

**Conventional Commits Quick Reference**:

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Code style (formatting, semicolons) |
| `refactor` | Code change that neither fixes nor adds |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `build` | Build system or dependencies |
| `ci` | CI/CD configuration |
| `chore` | Other changes (maintenance) |
| `revert` | Revert a previous commit |

**Examples**:
```
feat(helm): add support for custom ingress annotations
fix(k8s): resolve persistent volume claim binding issue
ci: update GitHub Actions to v4
docs: update installation instructions
```

#### 2.2 Create PR Validation Workflow

**File**: `.github/workflows/pr-validation.yaml`

```yaml
name: PR Validation
on:
  pull_request:
    branches: [master]

jobs:
  validate-release-pr:
    runs-on: ubuntu-latest
    steps:
      - name: Check source branch
        if: github.head_ref != 'dev'
        run: |
          echo "::error::Release PRs must come from the 'dev' branch"
          exit 1

      - name: Check for version label
        uses: mheap/github-action-required-labels@v5
        with:
          mode: exactly
          count: 1
          labels: "major, minor, patch"
          message: "PR must have exactly one label: major, minor, or patch"
```

#### 2.3 Create Release Workflow

**File**: `.github/workflows/release.yaml`

```yaml
name: Release
on:
  pull_request:
    types: [closed]
    branches: [master]
  workflow_dispatch:
    inputs:
      version-bump:
        description: 'Version bump type'
        required: true
        type: choice
        options:
          - major
          - minor
          - patch

jobs:
  # Job 1: Run smoke tests
  smoke-test:
    if: github.event.pull_request.merged == true || github.event_name == 'workflow_dispatch'
    uses: ./.github/workflows/test.yaml

  # Job 2: Prepare release (calculate version, etc.)
  prepare:
    needs: smoke-test
    runs-on: ubuntu-latest
    outputs:
      new_version: ${{ steps.bump.outputs.new_version }}
      bump_type: ${{ steps.determine.outputs.bump_type }}
    steps:
      - uses: actions/checkout@v4

      - name: Determine bump type
        id: determine
        run: |
          if [ "${{ github.event_name }}" == "workflow_dispatch" ]; then
            echo "bump_type=${{ inputs.version-bump }}" >> $GITHUB_OUTPUT
          else
            LABELS='${{ toJson(github.event.pull_request.labels.*.name) }}'
            if echo "$LABELS" | grep -q '"major"'; then
              echo "bump_type=major" >> $GITHUB_OUTPUT
            elif echo "$LABELS" | grep -q '"minor"'; then
              echo "bump_type=minor" >> $GITHUB_OUTPUT
            else
              echo "bump_type=patch" >> $GITHUB_OUTPUT
            fi
          fi

      - name: Calculate new version
        id: bump
        run: |
          CURRENT=$(grep '^version:' galaxy/Chart.yaml | awk '{print $2}')
          IFS='.' read -r major minor patch <<< "$CURRENT"

          case "${{ steps.determine.outputs.bump_type }}" in
            major) NEW_VERSION="$((major + 1)).0.0" ;;
            minor) NEW_VERSION="${major}.$((minor + 1)).0" ;;
            patch) NEW_VERSION="${major}.${minor}.$((patch + 1))" ;;
          esac

          echo "new_version=$NEW_VERSION" >> $GITHUB_OUTPUT
          echo "Bumping $CURRENT -> $NEW_VERSION"

  # Job 3: Manual approval gate
  approve-release:
    needs: prepare
    runs-on: ubuntu-latest
    environment: release
    steps:
      - name: Approval gate
        run: |
          echo "Release v${{ needs.prepare.outputs.new_version }} approved"
          echo "Proceeding with release..."

  # Job 4: Execute release
  release:
    needs: [prepare, approve-release]
    runs-on: ubuntu-latest
    env:
      NEW_VERSION: ${{ needs.prepare.outputs.new_version }}
    steps:
      # Generate token from GitHub App (bypasses branch protection rulesets)
      - name: Generate GitHub App token
        id: app-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.RELEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}
          repositories: galaxy-helm,helm-charts,galaxy-k8s-boot

      - uses: actions/checkout@v4
        with:
          token: ${{ steps.app-token.outputs.token }}
          fetch-depth: 0
          ref: master  # Explicitly checkout master to get merge commit

      - name: Configure git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Update Chart.yaml version
        run: |
          git pull origin master  # Ensure we have latest (including merge commit)
          sed -i "s/^version:.*/version: $NEW_VERSION/" galaxy/Chart.yaml
          git add galaxy/Chart.yaml
          git commit -m "chore(release): bump version to $NEW_VERSION"
          git push origin master

      - name: Install Helm
        run: curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

      - name: Package Helm chart
        run: |
          helm package galaxy/
          mv galaxy-${NEW_VERSION}.tgz /tmp/

      - name: Push to CloudVE/helm-charts
        env:
          APP_TOKEN: ${{ steps.app-token.outputs.token }}
        run: |
          git clone https://x-access-token:${APP_TOKEN}@github.com/CloudVE/helm-charts.git /tmp/helm-charts
          cp /tmp/galaxy-${NEW_VERSION}.tgz /tmp/helm-charts/
          cd /tmp/helm-charts
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          helm repo index . --merge index.yaml
          git add .
          git commit -m "Add galaxy-${NEW_VERSION}"
          git push

      - name: Create tag and release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}"
          git push origin "v${NEW_VERSION}"
          gh release create "v${NEW_VERSION}" \
            --title "release_${NEW_VERSION}" \
            --generate-notes \
            --latest

      - name: Merge master to dev
        run: |
          git checkout dev
          git merge master -m "Merge master back to dev after release v${NEW_VERSION}"
          git push origin dev

  # Job 5: Trigger downstream updates
  trigger-downstream:
    needs: [prepare, release]
    runs-on: ubuntu-latest
    steps:
      - name: Generate GitHub App token
        id: app-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.RELEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}
          repositories: galaxy-k8s-boot

      - name: Trigger galaxy-k8s-boot update
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ steps.app-token.outputs.token }}
          repository: galaxyproject/galaxy-k8s-boot
          event-type: update-galaxy-chart
          client-payload: '{"version": "${{ needs.prepare.outputs.new_version }}"}'

  # Job 6: Send notifications
  notify:
    needs: [prepare, release]
    runs-on: ubuntu-latest
    if: always()
    steps:
      - name: Slack notification
        uses: slackapi/slack-github-action@v1.26.0
        with:
          payload: |
            {
              "text": "Galaxy Helm Chart Release",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Galaxy Helm Chart v${{ needs.prepare.outputs.new_version }}* has been released!\n<${{ github.server_url }}/${{ github.repository }}/releases/tag/v${{ needs.prepare.outputs.new_version }}|View Release>"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK

      - name: Email notification
        uses: dawidd6/action-send-mail@v3
        with:
          server_address: ${{ secrets.SMTP_SERVER }}
          server_port: ${{ secrets.SMTP_PORT }}
          username: ${{ secrets.SMTP_USERNAME }}
          password: ${{ secrets.SMTP_PASSWORD }}
          subject: "Galaxy Helm Chart v${{ needs.prepare.outputs.new_version }} Released"
          to: ${{ secrets.RELEASE_NOTIFY_EMAILS }}
          from: "GitHub Actions <noreply@github.com>"
          body: |
            Galaxy Helm Chart version ${{ needs.prepare.outputs.new_version }} has been released.

            View the release: ${{ github.server_url }}/${{ github.repository }}/releases/tag/v${{ needs.prepare.outputs.new_version }}
```

---

### Phase 3: galaxy-helm-deps Workflows

#### 3.1 Create Smoke Test Workflow (K3S-based with K8s Version Matrix)

**File**: `.github/workflows/test.yaml`

```yaml
name: Linting and deployment test on K3S
on:
  push:
    branches: [master, dev]
  pull_request: {}
  workflow_dispatch: {}
  workflow_call: {}  # Allow calling from release workflow

jobs:
  linting:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Helm
        run: curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
      - name: Helm lint
        run: helm lint galaxy-deps/

  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        k8s-version:
          - v1.28.15+k3s1
          - v1.29.12+k3s1
          - v1.30.8+k3s1
          - v1.31.4+k3s1
          - v1.32.0+k3s1
    name: Test (K8s ${{ matrix.k8s-version }})
    steps:
      - uses: actions/checkout@v4

      - name: Install Helm
        run: curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

      - name: Start K3S (${{ matrix.k8s-version }})
        uses: jupyterhub/action-k3s-helm@v3
        with:
          k3s-version: ${{ matrix.k8s-version }}
          metrics-enabled: false
          traefik-enabled: false

      - name: Verify cluster
        run: |
          echo "Testing with Kubernetes version: ${{ matrix.k8s-version }}"
          kubectl version
          kubectl get nodes
          helm version

      - name: Update Helm dependencies
        run: helm dependency update galaxy-deps/

      - name: Install galaxy-deps
        run: |
          helm install galaxy-deps ./galaxy-deps \
            --create-namespace \
            --namespace galaxy-deps \
            --set cvmfs.cvmfscsi.cache.alien.enabled=false \
            --wait \
            --timeout=600s

      - name: Verify operators deployed
        run: |
          echo "Checking CloudNative-PG operator..."
          kubectl get pods -n galaxy-deps -l app.kubernetes.io/name=cloudnative-pg

          echo "Checking RabbitMQ operator..."
          kubectl get pods -n galaxy-deps -l app.kubernetes.io/name=rabbitmq-cluster-operator

      - name: Get all pods
        if: always()
        run: kubectl get pods -A

      - name: Get events
        if: always()
        run: kubectl get events -n galaxy-deps --sort-by='.lastTimestamp'
```

**Note on K8s Version Matrix**: The matrix tests against K8s versions 1.28 through 1.32. K3S releases follow Kubernetes releases - check https://github.com/k3s-io/k3s/tags for latest patch versions. Update these versions periodically.

#### 3.2 Create PR Validation Workflow

**File**: `.github/workflows/pr-validation.yaml`

Same structure as galaxy-helm (see Phase 2.1).

#### 3.3 Create Release Workflow

**File**: `.github/workflows/release.yaml`

Same structure as galaxy-helm (see Phase 2.2), with these modifications:
- Chart path: `galaxy-deps/` instead of `galaxy/`
- Chart name: `galaxy-deps` instead of `galaxy`
- Trigger event: `update-galaxy-deps` instead of `update-galaxy-chart`

---

### Phase 4: galaxy-k8s-boot Workflows

#### 4.1 Create Smoke Test Workflow (GCP VM-based)

**File**: `.github/workflows/smoke-test.yaml`

```yaml
name: Smoke Test (GCP VM)
on:
  pull_request:
    branches: [dev, master]
  workflow_dispatch: {}
  workflow_call: {}

jobs:
  smoke-test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write  # For GCP Workload Identity

    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to GCP
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Generate unique instance name
        id: instance
        run: echo "name=smoke-test-${{ github.run_id }}-${{ github.run_attempt }}" >> $GITHUB_OUTPUT

      - name: Create test VM
        run: |
          ./bin/launch_vm.sh \
            -k "${{ secrets.TEST_SSH_PUBLIC_KEY }}" \
            -p "${{ secrets.GCP_PROJECT }}" \
            -z "us-east4-c" \
            --ephemeral-only \
            ${{ steps.instance.outputs.name }}

      - name: Wait for Galaxy deployment
        run: |
          echo "Waiting for Galaxy to be ready..."
          # Poll the VM until Galaxy responds or timeout
          TIMEOUT=1800  # 30 minutes
          ELAPSED=0
          INTERVAL=30

          VM_IP=$(gcloud compute instances describe ${{ steps.instance.outputs.name }} \
            --zone=us-east4-c \
            --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

          while [ $ELAPSED -lt $TIMEOUT ]; do
            if curl -sf "http://${VM_IP}/galaxy/api/version" > /dev/null 2>&1; then
              echo "Galaxy is ready!"
              curl "http://${VM_IP}/galaxy/api/version" | jq .
              exit 0
            fi
            echo "Waiting... ($ELAPSED/$TIMEOUT seconds)"
            sleep $INTERVAL
            ELAPSED=$((ELAPSED + INTERVAL))
          done

          echo "Timeout waiting for Galaxy"
          exit 1

      - name: Cleanup VM
        if: always()
        run: |
          gcloud compute instances delete ${{ steps.instance.outputs.name }} \
            --zone=us-east4-c \
            --quiet || true
```

#### 4.2 Create PR Validation Workflow

**File**: `.github/workflows/pr-validation.yaml`

Same structure as galaxy-helm (see Phase 2.1).

#### 4.3 Create Release Workflow

**File**: `.github/workflows/release.yaml`

```yaml
name: Release
on:
  pull_request:
    types: [closed]
    branches: [master]
  workflow_dispatch:
    inputs:
      version-bump:
        description: 'Version bump type'
        required: true
        type: choice
        options:
          - major
          - minor
          - patch

jobs:
  smoke-test:
    if: github.event.pull_request.merged == true || github.event_name == 'workflow_dispatch'
    uses: ./.github/workflows/smoke-test.yaml
    secrets: inherit

  prepare:
    needs: smoke-test
    runs-on: ubuntu-latest
    outputs:
      new_version: ${{ steps.bump.outputs.new_version }}
    steps:
      - uses: actions/checkout@v4

      - name: Determine bump type
        id: determine
        run: |
          if [ "${{ github.event_name }}" == "workflow_dispatch" ]; then
            echo "bump_type=${{ inputs.version-bump }}" >> $GITHUB_OUTPUT
          else
            LABELS='${{ toJson(github.event.pull_request.labels.*.name) }}'
            if echo "$LABELS" | grep -q '"major"'; then
              echo "bump_type=major" >> $GITHUB_OUTPUT
            elif echo "$LABELS" | grep -q '"minor"'; then
              echo "bump_type=minor" >> $GITHUB_OUTPUT
            else
              echo "bump_type=patch" >> $GITHUB_OUTPUT
            fi
          fi

      - name: Calculate new version
        id: bump
        run: |
          CURRENT=$(cat VERSION | tr -d '[:space:]')
          IFS='.' read -r major minor patch <<< "$CURRENT"

          case "${{ steps.determine.outputs.bump_type }}" in
            major) NEW_VERSION="$((major + 1)).0.0" ;;
            minor) NEW_VERSION="${major}.$((minor + 1)).0" ;;
            patch) NEW_VERSION="${major}.${minor}.$((patch + 1))" ;;
          esac

          echo "new_version=$NEW_VERSION" >> $GITHUB_OUTPUT

  approve-release:
    needs: prepare
    runs-on: ubuntu-latest
    environment: release
    steps:
      - run: echo "Release v${{ needs.prepare.outputs.new_version }} approved"

  release:
    needs: [prepare, approve-release]
    runs-on: ubuntu-latest
    env:
      NEW_VERSION: ${{ needs.prepare.outputs.new_version }}
    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ secrets.RELEASE_TOKEN }}
          fetch-depth: 0

      - name: Configure git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Update VERSION file
        run: |
          echo "$NEW_VERSION" > VERSION
          git add VERSION
          git commit -m "Bump version to $NEW_VERSION"
          git push origin master

      - name: Create tag and release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}"
          git push origin "v${NEW_VERSION}"
          gh release create "v${NEW_VERSION}" \
            --title "release_${NEW_VERSION}" \
            --generate-notes \
            --latest

      - name: Merge master to dev
        run: |
          git checkout dev
          git merge master -m "Merge master back to dev after release v${NEW_VERSION}"
          git push origin dev

  notify:
    needs: [prepare, release]
    runs-on: ubuntu-latest
    if: always()
    steps:
      - name: Slack notification
        uses: slackapi/slack-github-action@v1.26.0
        with:
          payload: |
            {
              "text": "Galaxy K8S Boot Release",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Galaxy K8S Boot v${{ needs.prepare.outputs.new_version }}* has been released!\n<${{ github.server_url }}/${{ github.repository }}/releases/tag/v${{ needs.prepare.outputs.new_version }}|View Release>"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK

      - name: Email notification
        uses: dawidd6/action-send-mail@v3
        with:
          server_address: ${{ secrets.SMTP_SERVER }}
          server_port: ${{ secrets.SMTP_PORT }}
          username: ${{ secrets.SMTP_USERNAME }}
          password: ${{ secrets.SMTP_PASSWORD }}
          subject: "Galaxy K8S Boot v${{ needs.prepare.outputs.new_version }} Released"
          to: ${{ secrets.RELEASE_NOTIFY_EMAILS }}
          from: "GitHub Actions <noreply@github.com>"
          body: |
            Galaxy K8S Boot version ${{ needs.prepare.outputs.new_version }} has been released.

            View the release: ${{ github.server_url }}/${{ github.repository }}/releases/tag/v${{ needs.prepare.outputs.new_version }}
```

#### 4.4 Create Dependency Update Workflow

**File**: `.github/workflows/update-dependencies.yaml`

```yaml
name: Update Galaxy Dependencies
on:
  repository_dispatch:
    types: [update-galaxy-chart, update-galaxy-deps]
  workflow_dispatch:
    inputs:
      dependency:
        description: 'Which dependency to update'
        required: true
        type: choice
        options:
          - galaxy-chart
          - galaxy-deps
      version:
        description: 'New version'
        required: true

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: dev
          token: ${{ secrets.RELEASE_TOKEN }}

      - name: Determine dependency and version
        id: params
        run: |
          if [ "${{ github.event_name }}" == "repository_dispatch" ]; then
            if [ "${{ github.event.action }}" == "update-galaxy-chart" ]; then
              echo "dependency=galaxy-chart" >> $GITHUB_OUTPUT
              echo "var_name=GALAXY_CHART_VERSION" >> $GITHUB_OUTPUT
              echo "ansible_var=galaxy_chart_version" >> $GITHUB_OUTPUT
            else
              echo "dependency=galaxy-deps" >> $GITHUB_OUTPUT
              echo "var_name=GALAXY_DEPS_VERSION" >> $GITHUB_OUTPUT
              echo "ansible_var=galaxy_deps_version" >> $GITHUB_OUTPUT
            fi
            echo "version=${{ github.event.client_payload.version }}" >> $GITHUB_OUTPUT
          else
            echo "dependency=${{ inputs.dependency }}" >> $GITHUB_OUTPUT
            echo "version=${{ inputs.version }}" >> $GITHUB_OUTPUT
            if [ "${{ inputs.dependency }}" == "galaxy-chart" ]; then
              echo "var_name=GALAXY_CHART_VERSION" >> $GITHUB_OUTPUT
              echo "ansible_var=galaxy_chart_version" >> $GITHUB_OUTPUT
            else
              echo "var_name=GALAXY_DEPS_VERSION" >> $GITHUB_OUTPUT
              echo "ansible_var=galaxy_deps_version" >> $GITHUB_OUTPUT
            fi
          fi

      - name: Update launch_vm.sh
        run: |
          sed -i 's/^${{ steps.params.outputs.var_name }}=.*/${{ steps.params.outputs.var_name }}="${{ steps.params.outputs.version }}"/' bin/launch_vm.sh

      - name: Update Ansible defaults
        run: |
          sed -i 's/^${{ steps.params.outputs.ansible_var }}:.*/${{ steps.params.outputs.ansible_var }}: "${{ steps.params.outputs.version }}"/' \
            roles/galaxy_k8s_deployment/defaults/main.yml

      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v6
        with:
          token: ${{ secrets.RELEASE_TOKEN }}
          branch: update-${{ steps.params.outputs.dependency }}-${{ steps.params.outputs.version }}
          title: "Update ${{ steps.params.outputs.dependency }} to ${{ steps.params.outputs.version }}"
          body: |
            Automated update triggered by release of ${{ steps.params.outputs.dependency }} v${{ steps.params.outputs.version }}.

            ## Changes
            - Updated `${{ steps.params.outputs.var_name }}` in `bin/launch_vm.sh`
            - Updated `${{ steps.params.outputs.ansible_var }}` in `roles/galaxy_k8s_deployment/defaults/main.yml`

            ## Triggered by
            - Repository: ${{ github.event.client_payload.repository || 'manual' }}
            - Workflow run: ${{ github.event.client_payload.run_url || 'N/A' }}
          base: dev
          labels: |
            automated
            dependency-update
```

---

### Phase 4a: galaxykubeman-helm Workflows

The galaxykubeman-helm chart depends on galaxy-helm and is deployed to CloudVE/helm-charts. No other repositories depend on it.

#### 4a.1 Create Test Workflow (K3S-based with K8s Version Matrix)

**File**: `.github/workflows/test.yaml`

```yaml
name: Linting and deployment test on K3S
on:
  push:
    branches: [master, dev]
  pull_request: {}
  workflow_dispatch: {}
  workflow_call: {}

jobs:
  linting:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Helm
        run: curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
      - name: Update Helm dependencies
        run: helm dependency update galaxykubeman/
      - name: Helm lint
        run: helm lint galaxykubeman/

  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        k8s-version:
          - v1.28.15+k3s1
          - v1.29.12+k3s1
          - v1.30.8+k3s1
          - v1.31.4+k3s1
          - v1.32.0+k3s1
    name: Test (K8s ${{ matrix.k8s-version }})
    steps:
      - uses: actions/checkout@v4

      - name: Install Helm
        run: curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

      - name: Start K3S (${{ matrix.k8s-version }})
        uses: jupyterhub/action-k3s-helm@v3
        with:
          k3s-version: ${{ matrix.k8s-version }}
          metrics-enabled: false
          traefik-enabled: false

      - name: Verify cluster
        run: |
          echo "Testing with Kubernetes version: ${{ matrix.k8s-version }}"
          kubectl version
          kubectl get nodes
          helm version

      - name: Update Helm dependencies
        run: helm dependency update galaxykubeman/

      - name: Install galaxykubeman (dry-run)
        run: |
          helm install galaxykubeman ./galaxykubeman \
            --create-namespace \
            --namespace galaxykubeman \
            --dry-run

      - name: Get all pods
        if: always()
        run: kubectl get pods -A
```

#### 4a.2 Create PR Validation Workflow

**File**: `.github/workflows/pr-validation.yaml`

Same structure as galaxy-helm (see Phase 2.2).

#### 4a.3 Create Release Workflow

**File**: `.github/workflows/release.yaml`

Same structure as galaxy-helm (see Phase 2.3), with these modifications:
- Chart path: `galaxykubeman/` instead of `galaxy/`
- Chart name: `galaxykubeman` instead of `galaxy`
- No downstream triggers (nothing depends on this chart)

---

### Phase 4b: galaxy-cvmfs-csi-helm Workflows

The galaxy-cvmfs-csi-helm chart has no external dependencies but is a dependency of galaxy-helm-deps. When released, it should trigger a PR to update the dependency version in galaxy-helm-deps.

#### 4b.1 Create Test Workflow (K3S-based with K8s Version Matrix)

**File**: `.github/workflows/test.yaml`

```yaml
name: Linting and deployment test on K3S
on:
  push:
    branches: [master, dev]
  pull_request: {}
  workflow_dispatch: {}
  workflow_call: {}

jobs:
  linting:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Helm
        run: curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
      - name: Update Helm dependencies
        run: helm dependency update galaxy-cvmfs-csi/
      - name: Helm lint
        run: helm lint galaxy-cvmfs-csi/

  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        k8s-version:
          - v1.28.15+k3s1
          - v1.29.12+k3s1
          - v1.30.8+k3s1
          - v1.31.4+k3s1
          - v1.32.0+k3s1
    name: Test (K8s ${{ matrix.k8s-version }})
    steps:
      - uses: actions/checkout@v4

      - name: Install Helm
        run: curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

      - name: Start K3S (${{ matrix.k8s-version }})
        uses: jupyterhub/action-k3s-helm@v3
        with:
          k3s-version: ${{ matrix.k8s-version }}
          metrics-enabled: false
          traefik-enabled: false

      - name: Verify cluster
        run: |
          echo "Testing with Kubernetes version: ${{ matrix.k8s-version }}"
          kubectl version
          kubectl get nodes
          helm version

      - name: Update Helm dependencies
        run: helm dependency update galaxy-cvmfs-csi/

      - name: Install galaxy-cvmfs-csi
        run: |
          helm install galaxy-cvmfs-csi ./galaxy-cvmfs-csi \
            --create-namespace \
            --namespace cvmfs \
            --set cvmfscsi.cache.alien.enabled=false \
            --wait \
            --timeout=600s

      - name: Verify CSI driver deployed
        run: |
          echo "Checking CVMFS CSI driver..."
          kubectl get pods -n cvmfs
          kubectl get csidrivers

      - name: Get all pods
        if: always()
        run: kubectl get pods -A

      - name: Get events
        if: always()
        run: kubectl get events -n cvmfs --sort-by='.lastTimestamp'
```

#### 4b.2 Create PR Validation Workflow

**File**: `.github/workflows/pr-validation.yaml`

Same structure as galaxy-helm (see Phase 2.2).

#### 4b.3 Create Release Workflow

**File**: `.github/workflows/release.yaml`

Same structure as galaxy-helm (see Phase 2.3), with these modifications:
- Chart path: `galaxy-cvmfs-csi/` instead of `galaxy/`
- Chart name: `galaxy-cvmfs-csi` instead of `galaxy`
- Trigger event: `update-cvmfs-csi` to galaxy-helm-deps instead of galaxy-k8s-boot

Add to the `trigger-downstream` job:

```yaml
  trigger-downstream:
    needs: [prepare, release]
    runs-on: ubuntu-latest
    steps:
      - name: Trigger galaxy-helm-deps update
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.RELEASE_TOKEN }}
          repository: galaxyproject/galaxy-helm-deps
          event-type: update-cvmfs-csi
          client-payload: '{"version": "${{ needs.prepare.outputs.new_version }}"}'
```

#### 4b.4 Add Dependency Update Handler to galaxy-helm-deps

**File**: `.github/workflows/update-dependencies.yaml` (in galaxy-helm-deps)

```yaml
name: Update Chart Dependencies
on:
  repository_dispatch:
    types: [update-cvmfs-csi]
  workflow_dispatch:
    inputs:
      dependency:
        description: 'Which dependency to update'
        required: true
        type: choice
        options:
          - galaxy-cvmfs-csi
      version:
        description: 'New version'
        required: true

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: dev
          token: ${{ secrets.RELEASE_TOKEN }}

      - name: Install yq
        run: |
          sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq

      - name: Determine dependency and version
        id: params
        run: |
          if [ "${{ github.event_name }}" == "repository_dispatch" ]; then
            echo "dependency=galaxy-cvmfs-csi" >> $GITHUB_OUTPUT
            echo "version=${{ github.event.client_payload.version }}" >> $GITHUB_OUTPUT
          else
            echo "dependency=${{ inputs.dependency }}" >> $GITHUB_OUTPUT
            echo "version=${{ inputs.version }}" >> $GITHUB_OUTPUT
          fi

      - name: Update Chart.yaml dependency version
        run: |
          yq e '(.dependencies[] | select(.name == "${{ steps.params.outputs.dependency }}")).version = "${{ steps.params.outputs.version }}"' \
            -i galaxy-deps/Chart.yaml

      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v6
        with:
          token: ${{ secrets.RELEASE_TOKEN }}
          branch: update-${{ steps.params.outputs.dependency }}-${{ steps.params.outputs.version }}
          title: "Update ${{ steps.params.outputs.dependency }} to ${{ steps.params.outputs.version }}"
          body: |
            Automated update triggered by release of ${{ steps.params.outputs.dependency }} v${{ steps.params.outputs.version }}.

            ## Changes
            - Updated `${{ steps.params.outputs.dependency }}` version in `galaxy-deps/Chart.yaml`

            ## Triggered by
            - Repository: ${{ github.event.client_payload.repository || 'manual' }}
            - Workflow run: ${{ github.event.client_payload.run_url || 'N/A' }}
          base: dev
          labels: |
            automated
            dependency-update
```

---

### Phase 4c: galaxy-docker-k8s Workflows

The galaxy-docker-k8s repository is an Ansible playbook used when building the Galaxy Docker image. When released, it should trigger a PR to the upstream Galaxy repository to update the `GALAXY_PLAYBOOK_BRANCH` ARG in `.k8s_ci.Dockerfile`.

**Note**: This repository uses tags (e.g., `v4.2.0`) rather than a VERSION file for versioning.

#### 4c.1 Create Test Workflow

**File**: `.github/workflows/test.yaml`

```yaml
name: Ansible Lint and Syntax Check
on:
  push:
    branches: [master, dev]
  pull_request: {}
  workflow_dispatch: {}
  workflow_call: {}

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        run: |
          pip install ansible ansible-lint

      - name: Install Ansible Galaxy requirements
        run: ansible-galaxy install -r requirements.yml -p roles --force-with-deps

      - name: Run ansible-lint
        run: ansible-lint playbook.yml

      - name: Syntax check
        run: ansible-playbook playbook.yml --syntax-check
```

#### 4c.2 Create PR Validation Workflow

**File**: `.github/workflows/pr-validation.yaml`

Same structure as galaxy-helm (see Phase 2.2).

#### 4c.3 Create Release Workflow

**File**: `.github/workflows/release.yaml`

```yaml
name: Release
on:
  pull_request:
    types: [closed]
    branches: [master]
  workflow_dispatch:
    inputs:
      version-bump:
        description: 'Version bump type'
        required: true
        type: choice
        options:
          - major
          - minor
          - patch

jobs:
  test:
    if: github.event.pull_request.merged == true || github.event_name == 'workflow_dispatch'
    uses: ./.github/workflows/test.yaml

  prepare:
    needs: test
    runs-on: ubuntu-latest
    outputs:
      new_version: ${{ steps.bump.outputs.new_version }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Determine bump type
        id: determine
        run: |
          if [ "${{ github.event_name }}" == "workflow_dispatch" ]; then
            echo "bump_type=${{ inputs.version-bump }}" >> $GITHUB_OUTPUT
          else
            LABELS='${{ toJson(github.event.pull_request.labels.*.name) }}'
            if echo "$LABELS" | grep -q '"major"'; then
              echo "bump_type=major" >> $GITHUB_OUTPUT
            elif echo "$LABELS" | grep -q '"minor"'; then
              echo "bump_type=minor" >> $GITHUB_OUTPUT
            else
              echo "bump_type=patch" >> $GITHUB_OUTPUT
            fi
          fi

      - name: Get latest tag and calculate new version
        id: bump
        run: |
          # Get latest tag, default to v0.0.0 if none exist
          LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
          CURRENT=${LATEST_TAG#v}
          IFS='.' read -r major minor patch <<< "$CURRENT"

          case "${{ steps.determine.outputs.bump_type }}" in
            major) NEW_VERSION="$((major + 1)).0.0" ;;
            minor) NEW_VERSION="${major}.$((minor + 1)).0" ;;
            patch) NEW_VERSION="${major}.${minor}.$((patch + 1))" ;;
          esac

          echo "new_version=$NEW_VERSION" >> $GITHUB_OUTPUT
          echo "Bumping $CURRENT -> $NEW_VERSION"

  approve-release:
    needs: prepare
    runs-on: ubuntu-latest
    environment: release
    steps:
      - run: echo "Release v${{ needs.prepare.outputs.new_version }} approved"

  release:
    needs: [prepare, approve-release]
    runs-on: ubuntu-latest
    env:
      NEW_VERSION: ${{ needs.prepare.outputs.new_version }}
    steps:
      - uses: actions/checkout@v4
        with:
          token: ${{ secrets.RELEASE_TOKEN }}
          fetch-depth: 0

      - name: Configure git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Create tag and release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          git tag -a "v${NEW_VERSION}" -m "Release v${NEW_VERSION}"
          git push origin "v${NEW_VERSION}"
          gh release create "v${NEW_VERSION}" \
            --title "release_${NEW_VERSION}" \
            --generate-notes \
            --latest

      - name: Merge master to dev
        run: |
          git checkout dev
          git merge master -m "Merge master back to dev after release v${NEW_VERSION}"
          git push origin dev

  trigger-downstream:
    needs: [prepare, release]
    runs-on: ubuntu-latest
    steps:
      - name: Trigger Galaxy repository update
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.RELEASE_TOKEN }}
          repository: galaxyproject/galaxy
          event-type: update-k8s-playbook
          client-payload: '{"version": "v${{ needs.prepare.outputs.new_version }}"}'

  notify:
    needs: [prepare, release]
    runs-on: ubuntu-latest
    if: always()
    steps:
      - name: Slack notification
        uses: slackapi/slack-github-action@v1.26.0
        with:
          payload: |
            {
              "text": "Galaxy Docker K8S Playbook Release",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Galaxy Docker K8S v${{ needs.prepare.outputs.new_version }}* has been released!\n<${{ github.server_url }}/${{ github.repository }}/releases/tag/v${{ needs.prepare.outputs.new_version }}|View Release>"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK
```

#### 4c.4 Create Update Handler in Galaxy Repository

**File**: `.github/workflows/update-k8s-playbook.yaml` (in galaxyproject/galaxy)

```yaml
name: Update K8S Playbook Version
on:
  repository_dispatch:
    types: [update-k8s-playbook]
  workflow_dispatch:
    inputs:
      version:
        description: 'New playbook version (e.g., v4.3.0)'
        required: true

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: dev
          token: ${{ secrets.RELEASE_TOKEN }}

      - name: Determine version
        id: params
        run: |
          if [ "${{ github.event_name }}" == "repository_dispatch" ]; then
            echo "version=${{ github.event.client_payload.version }}" >> $GITHUB_OUTPUT
          else
            echo "version=${{ inputs.version }}" >> $GITHUB_OUTPUT
          fi

      - name: Update .k8s_ci.Dockerfile
        run: |
          sed -i 's/^ARG GALAXY_PLAYBOOK_BRANCH=.*/ARG GALAXY_PLAYBOOK_BRANCH=${{ steps.params.outputs.version }}/' .k8s_ci.Dockerfile

      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v6
        with:
          token: ${{ secrets.RELEASE_TOKEN }}
          branch: update-k8s-playbook-${{ steps.params.outputs.version }}
          title: "Update K8S playbook to ${{ steps.params.outputs.version }}"
          body: |
            Automated update triggered by release of galaxy-docker-k8s ${{ steps.params.outputs.version }}.

            ## Changes
            - Updated `GALAXY_PLAYBOOK_BRANCH` in `.k8s_ci.Dockerfile` to `${{ steps.params.outputs.version }}`

            ## Triggered by
            - Repository: galaxyproject/galaxy-docker-k8s
            - Workflow run: ${{ github.event.client_payload.run_url || 'N/A' }}
          base: dev
          labels: |
            automated
            k8s
            docker
```

---

## Workflow Diagrams

### Development Flow
```
Feature Branch → PR to dev → Smoke Test → Merge to dev
```

### Release Flow
```
dev → PR to master (with major/minor/patch label)
  │
  ├─→ PR Validation (check label, source branch)
  │
  └─→ On Merge:
        │
        ├─→ Run Smoke Tests
        │
        ├─→ Prepare Release (calculate version)
        │
        ├─→ ⏸️  MANUAL APPROVAL REQUIRED (GitHub Environment)
        │
        ├─→ Execute Release:
        │     ├─ Update version file
        │     ├─ Package chart (helm repos only)
        │     ├─ Push to CloudVE/helm-charts (helm repos only)
        │     ├─ Create git tag
        │     ├─ Create GitHub release
        │     └─ Merge master → dev
        │
        ├─→ Trigger Downstream PRs (helm repos only)
        │
        └─→ Send Notifications (Slack + Email)
```

---

## Required Secrets

**Recommended**: Store GitHub App secrets as **organization-level secrets** to avoid duplicating the private key across repositories. Grant access only to repositories that need release automation.

| Scope | Secret Name | Purpose |
|-------|-------------|---------|
| Organization | `RELEASE_APP_ID` | GitHub App ID for release automation |
| Organization | `RELEASE_APP_PRIVATE_KEY` | GitHub App private key (.pem file contents) |
| All repos | `SLACK_WEBHOOK_URL` | Slack notifications to #galaxy-k8s-sig |
| All repos | `SMTP_SERVER` | Email server address |
| All repos | `SMTP_PORT` | Email server port |
| All repos | `SMTP_USERNAME` | Email authentication |
| All repos | `SMTP_PASSWORD` | Email authentication |
| All repos | `RELEASE_NOTIFY_EMAILS` | Comma-separated list of repo owner emails |
| galaxy-k8s-boot | `GCP_WORKLOAD_IDENTITY_PROVIDER` | GCP authentication |
| galaxy-k8s-boot | `GCP_SERVICE_ACCOUNT` | GCP service account |
| galaxy-k8s-boot | `GCP_PROJECT` | GCP project ID |
| galaxy-k8s-boot | `TEST_SSH_PUBLIC_KEY` | SSH key for test VMs |

---

## Required GitHub Environments

Each repository needs a `release` environment configured with:

1. **Required reviewers**: Add repository owners/maintainers
2. **Wait timer** (optional): 5 minutes to allow cancellation
3. **Deployment branches**: Limit to `master` branch

---

## Implementation Checklist

### Prerequisites
- [ ] Create GitHub App for release automation (see Phase 1.1)
- [ ] Install GitHub App on all repositories
- [ ] Add `RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY` secrets to all repos
- [ ] Create Slack webhook for #galaxy-k8s-sig
- [ ] Configure email secrets (SMTP) in all repos
- [ ] Create `release` environment with required reviewers in all repos
- [ ] Create GitHub team `@galaxyproject/galaxy-k8s-maintainers`

### All Repositories (shared)
- [ ] Create `.github/workflows/commit-lint.yaml`
- [ ] Create `.github/dependabot.yml`
- [ ] Create `.github/CODEOWNERS`
- [ ] Create required labels (major, minor, patch, dependencies, etc.)
- [ ] Configure repository rulesets for `master` (with GitHub App bypass)
- [ ] Configure repository rulesets for `dev` (with GitHub App bypass)
- [ ] Add version badges to README.md

### galaxy-helm
- [ ] Create `.github/workflows/pr-validation.yaml`
- [ ] Create `.github/workflows/release.yaml`
- [ ] Create `.github/workflows/check-helm-deps.yaml`
- [ ] Update `.github/workflows/test.yaml` with K8s version matrix
- [ ] Configure `release` environment
- [ ] Add notification secrets

### galaxy-helm-deps
- [ ] Create `.github/workflows/test.yaml` (K3S smoke test with K8s matrix)
- [ ] Create `.github/workflows/pr-validation.yaml`
- [ ] Create `.github/workflows/release.yaml`
- [ ] Create `.github/workflows/check-helm-deps.yaml`
- [ ] Configure `release` environment
- [ ] Add notification secrets

### galaxy-k8s-boot
- [ ] Create `.github/workflows/smoke-test.yaml` (GCP VM)
- [ ] Create `.github/workflows/pr-validation.yaml`
- [ ] Create `.github/workflows/release.yaml`
- [ ] Create `.github/workflows/update-dependencies.yaml`
- [ ] Create `.github/workflows/version-dashboard.yaml`
- [ ] Configure `release` environment
- [ ] Add GCP and notification secrets

### galaxykubeman-helm
- [ ] Create `.github/workflows/test.yaml` (K3S smoke test with K8s matrix)
- [ ] Create `.github/workflows/pr-validation.yaml`
- [ ] Create `.github/workflows/release.yaml`
- [ ] Remove deprecated `packaging.yml`
- [ ] Configure `release` environment
- [ ] Add notification secrets

### galaxy-cvmfs-csi-helm
- [ ] Create `.github/workflows/test.yaml` (K3S smoke test with K8s matrix)
- [ ] Create `.github/workflows/pr-validation.yaml`
- [ ] Create `.github/workflows/release.yaml`
- [ ] Remove deprecated `packaging.yml`
- [ ] Configure `release` environment
- [ ] Add notification secrets

### galaxy-docker-k8s
- [ ] Create `.github/workflows/test.yaml` (Ansible lint)
- [ ] Create `.github/workflows/pr-validation.yaml`
- [ ] Create `.github/workflows/release.yaml`
- [ ] Configure `release` environment
- [ ] Add notification secrets

### galaxy (upstream - for dependency update handler only)
- [ ] Create `.github/workflows/update-k8s-playbook.yaml`

---

## Files Summary

| Repository | File | Action |
|------------|------|--------|
| **All repos** | `.github/workflows/commit-lint.yaml` | Create |
| **All repos** | `.github/dependabot.yml` | Create |
| **All repos** | `.github/CODEOWNERS` | Create |
| galaxy-helm | `.github/workflows/pr-validation.yaml` | Create |
| galaxy-helm | `.github/workflows/release.yaml` | Create |
| galaxy-helm | `.github/workflows/check-helm-deps.yaml` | Create |
| galaxy-helm | `.github/workflows/test.yaml` | Modify (add K8s matrix) |
| galaxy-helm-deps | `.github/workflows/test.yaml` | Create (with K8s matrix) |
| galaxy-helm-deps | `.github/workflows/pr-validation.yaml` | Create |
| galaxy-helm-deps | `.github/workflows/release.yaml` | Create |
| galaxy-helm-deps | `.github/workflows/check-helm-deps.yaml` | Create |
| galaxy-k8s-boot | `.github/workflows/smoke-test.yaml` | Create |
| galaxy-k8s-boot | `.github/workflows/pr-validation.yaml` | Create |
| galaxy-k8s-boot | `.github/workflows/release.yaml` | Create |
| galaxy-k8s-boot | `.github/workflows/update-dependencies.yaml` | Create |
| galaxy-k8s-boot | `.github/workflows/version-dashboard.yaml` | Create |
| galaxykubeman-helm | `.github/workflows/test.yaml` | Create (with K8s matrix) |
| galaxykubeman-helm | `.github/workflows/pr-validation.yaml` | Create |
| galaxykubeman-helm | `.github/workflows/release.yaml` | Create |
| galaxykubeman-helm | `.github/workflows/packaging.yml` | Delete (deprecated) |
| galaxy-cvmfs-csi-helm | `.github/workflows/test.yaml` | Create (with K8s matrix) |
| galaxy-cvmfs-csi-helm | `.github/workflows/pr-validation.yaml` | Create |
| galaxy-cvmfs-csi-helm | `.github/workflows/release.yaml` | Create |
| galaxy-cvmfs-csi-helm | `.github/workflows/packaging.yml` | Delete (deprecated) |
| galaxy-docker-k8s | `.github/workflows/test.yaml` | Create |
| galaxy-docker-k8s | `.github/workflows/pr-validation.yaml` | Create |
| galaxy-docker-k8s | `.github/workflows/release.yaml` | Create |
| galaxy-helm-deps | `.github/workflows/update-dependencies.yaml` | Create |
| galaxy (upstream) | `.github/workflows/update-k8s-playbook.yaml` | Create |

**Total: 31 workflow files across 7 repositories (plus shared files)**

---

## Pre-Release Support (Future Enhancement)

While not implemented now, here's what pre-release support might look like:

### Version Format
```
Stable:      1.2.3
Pre-release: 1.2.3-rc.1, 1.2.3-beta.1, 1.2.3-alpha.1
```

### Workflow Changes

1. **Additional Labels**: Add `pre-release` label option alongside `major/minor/patch`

2. **Version Calculation**:
```yaml
- name: Calculate version
  run: |
    if [ "$BUMP_TYPE" == "pre-release" ]; then
      # If already a pre-release, increment rc number
      # If stable, create first rc of next patch
      if [[ "$CURRENT" =~ -rc\.([0-9]+)$ ]]; then
        RC_NUM=$((${BASH_REMATCH[1]} + 1))
        NEW_VERSION="${CURRENT%-rc.*}-rc.${RC_NUM}"
      else
        NEW_VERSION="${major}.${minor}.$((patch + 1))-rc.1"
      fi
    fi
```

3. **GitHub Release Flags**:
```yaml
- name: Create release
  run: |
    FLAGS="--generate-notes"
    if [[ "$NEW_VERSION" =~ -(rc|beta|alpha) ]]; then
      FLAGS="$FLAGS --prerelease"
    else
      FLAGS="$FLAGS --latest"
    fi
    gh release create "v${NEW_VERSION}" $FLAGS
```

4. **Helm Chart Repository**:
   - Pre-releases could go to a separate channel/index
   - Or use `--devel` flag support in index.yaml

5. **Skip Downstream Triggers**:
   - Pre-releases should NOT trigger galaxy-k8s-boot updates
   - Only stable releases should cascade downstream

6. **Notification Differentiation**:
   - Different Slack channel for pre-releases
   - Different email list (testers vs all stakeholders)

### Configuration Example
```yaml
inputs:
  version-bump:
    type: choice
    options:
      - major
      - minor
      - patch
      - rc        # Release candidate
      - promote   # Promote current rc to stable
```

---

## Phase 5: Repository Rulesets

Configure repository rulesets (not classic branch protection) to enforce the release process. Rulesets are preferred because they support bypass lists for GitHub Apps, allowing the release bot to push to protected branches while enforcing rules for all other users including admins.

### 5.1 Master Branch Ruleset

**Create Ruleset** (GitHub → Repository → Settings → Rules → Rulesets → New ruleset):

| Setting | Value | Reason |
|---------|-------|--------|
| **Ruleset name** | `Protect master` | Descriptive name |
| **Enforcement status** | Active | Enable immediately |
| **Bypass list** | Add `galaxy-release-bot` (GitHub App) | Allow release automation |
| **Target branches** | Include `refs/heads/master` | Protect release branch |

**Rules to enable**:

| Rule | Configuration | Reason |
|------|---------------|--------|
| Restrict deletions | ✅ Enabled | Protect branch from deletion |
| Require a pull request | ✅ Enabled | No direct pushes |
| → Required approvals | 1 | Peer review required |
| → Dismiss stale reviews | ✅ Yes | Re-review after changes |
| → Require review from Code Owners | ✅ Yes | Designated maintainers |
| → Require conversation resolution | ✅ Yes | Address all feedback |
| Require status checks | ✅ Enabled | CI must pass |
| → Required checks | `lint-pr-title`, `validate-release-pr`, `lint`, `test` | |
| → Require branches to be up to date | ✅ Yes | Prevent merge conflicts |
| Block force pushes | ✅ Enabled | Protect history |

### 5.2 Dev Branch Ruleset

**Create Ruleset**:

| Setting | Value | Reason |
|---------|-------|--------|
| **Ruleset name** | `Protect dev` | Descriptive name |
| **Enforcement status** | Active | Enable immediately |
| **Bypass list** | Add `galaxy-release-bot` (GitHub App) | Allow merge back after release |
| **Target branches** | Include `refs/heads/dev` | Protect development branch |

**Rules to enable**:

| Rule | Configuration | Reason |
|------|---------------|--------|
| Restrict deletions | ✅ Enabled | Protect branch |
| Require a pull request | ✅ Enabled | No direct pushes |
| → Required approvals | 1 | Peer review |
| Require status checks | ✅ Enabled | CI must pass |
| → Required checks | `lint-pr-title`, `lint-commits`, `lint`, `test` | |
| → Require branches to be up to date | ❌ No | Allow parallel PRs |
| Block force pushes | ✅ Enabled | Protect history |

### 5.3 CODEOWNERS File

Create `.github/CODEOWNERS` in each repository:

```
# Default owners for everything
* @galaxyproject/galaxy-k8s-maintainers

# Helm chart specific
/galaxy/ @galaxyproject/galaxy-k8s-maintainers
/galaxy-deps/ @galaxyproject/galaxy-k8s-maintainers

# CI/CD configuration
/.github/ @galaxyproject/galaxy-k8s-maintainers

# Ansible roles
/roles/ @galaxyproject/galaxy-k8s-maintainers
```

### 5.4 Required Labels

Create the following labels in each repository:

| Label | Color | Description |
|-------|-------|-------------|
| `major` | `#d73a4a` (red) | Major version bump (breaking changes) |
| `minor` | `#0e8a16` (green) | Minor version bump (new features) |
| `patch` | `#1d76db` (blue) | Patch version bump (bug fixes) |
| `dependencies` | `#0366d6` | Dependency updates |
| `github-actions` | `#000000` | GitHub Actions updates |
| `automated` | `#ededed` | Automated PRs |
| `work-in-progress` | `#fbca04` | WIP - do not merge |

### 5.5 Ruleset Setup Script

Run this script using GitHub CLI to configure repository rulesets. Requires the GitHub App ID to be set as an environment variable.

```bash
#!/bin/bash
# configure-rulesets.sh
#
# Usage: RELEASE_APP_ID=123456 ./configure-rulesets.sh

set -e

if [ -z "${RELEASE_APP_ID}" ]; then
    echo "ERROR: RELEASE_APP_ID environment variable is required"
    echo "Usage: RELEASE_APP_ID=<app-id> ./configure-rulesets.sh"
    exit 1
fi

REPOS=(
  "galaxyproject/galaxy-helm"
  "galaxyproject/galaxy-helm-deps"
  "galaxyproject/galaxy-k8s-boot"
  "galaxyproject/galaxykubeman-helm"
  "CloudVE/galaxy-cvmfs-csi-helm"
  "galaxyproject/galaxy-docker-k8s"
)

# Bypass actors configuration (GitHub App)
BYPASS_ACTORS="[{\"actor_id\": ${RELEASE_APP_ID}, \"actor_type\": \"Integration\", \"bypass_mode\": \"always\"}]"

create_ruleset() {
    local repo=$1
    local name=$2
    local branch=$3
    local strict=$4
    local checks=$5
    local dismiss_stale=$6

    echo "  Creating ruleset '${name}' for ${branch}..."

    # Build status checks array
    local status_checks=""
    for check in $(echo "$checks" | jq -r '.[]'); do
        if [ -n "$status_checks" ]; then
            status_checks="${status_checks},"
        fi
        status_checks="${status_checks}{\"context\": \"${check}\", \"integration_id\": null}"
    done

    gh api -X POST "repos/${repo}/rulesets" --input - <<EOF
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
                "required_review_thread_resolution": true
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
}

for REPO in "${REPOS[@]}"; do
    echo "Configuring $REPO..."

    # Delete existing rulesets
    for id in $(gh api "repos/${REPO}/rulesets" --jq '.[].id' 2>/dev/null || echo ""); do
        echo "  Deleting existing ruleset ${id}..."
        gh api -X DELETE "repos/${REPO}/rulesets/${id}"
    done

    # Master branch ruleset (stricter)
    create_ruleset \
        "${REPO}" \
        "Protect master" \
        "master" \
        "true" \
        '["lint-pr-title", "lint-commits", "lint", "test", "validate-release-pr"]' \
        "true"

    # Dev branch ruleset (less strict)
    create_ruleset \
        "${REPO}" \
        "Protect dev" \
        "dev" \
        "false" \
        '["lint-pr-title", "lint-commits", "lint", "test"]' \
        "false"

    echo "Done with $REPO"
done

echo ""
echo "Rulesets configured successfully!"
echo "View rulesets: https://github.com/<org>/<repo>/settings/rules"
```

---

## Phase 6: Version Synchronization Dashboard

### 6.1 Version Badges for READMEs

Add version badges to each repository's README.md:

**galaxy-helm README.md**:
```markdown
# Galaxy Helm Chart

![Version](https://img.shields.io/github/v/release/galaxyproject/galaxy-helm?label=chart%20version)
![Kubernetes](https://img.shields.io/badge/kubernetes-1.28%20--%201.32-blue)
![Galaxy](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/galaxyproject/galaxy-helm/master/galaxy/Chart.yaml&query=$.appVersion&label=galaxy%20version)

[![CI](https://github.com/galaxyproject/galaxy-helm/actions/workflows/test.yaml/badge.svg)](https://github.com/galaxyproject/galaxy-helm/actions/workflows/test.yaml)
[![Release](https://github.com/galaxyproject/galaxy-helm/actions/workflows/release.yaml/badge.svg)](https://github.com/galaxyproject/galaxy-helm/actions/workflows/release.yaml)
```

**galaxy-helm-deps README.md**:
```markdown
# Galaxy Helm Dependencies

![Version](https://img.shields.io/github/v/release/galaxyproject/galaxy-helm-deps?label=chart%20version)
![Kubernetes](https://img.shields.io/badge/kubernetes-1.28%20--%201.32-blue)

[![CI](https://github.com/galaxyproject/galaxy-helm-deps/actions/workflows/test.yaml/badge.svg)](https://github.com/galaxyproject/galaxy-helm-deps/actions/workflows/test.yaml)
[![Release](https://github.com/galaxyproject/galaxy-helm-deps/actions/workflows/release.yaml/badge.svg)](https://github.com/galaxyproject/galaxy-helm-deps/actions/workflows/release.yaml)
```

**galaxy-k8s-boot README.md**:
```markdown
# Galaxy K8S Boot

![Version](https://img.shields.io/github/v/release/galaxyproject/galaxy-k8s-boot?label=version)
![Galaxy Helm](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/galaxyproject/galaxy-k8s-boot/master/roles/galaxy_k8s_deployment/defaults/main.yml&query=$.galaxy_chart_version&label=galaxy-helm)
![Galaxy Deps](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/galaxyproject/galaxy-k8s-boot/master/roles/galaxy_k8s_deployment/defaults/main.yml&query=$.galaxy_deps_version&label=galaxy-deps)

[![Smoke Test](https://github.com/galaxyproject/galaxy-k8s-boot/actions/workflows/smoke-test.yaml/badge.svg)](https://github.com/galaxyproject/galaxy-k8s-boot/actions/workflows/smoke-test.yaml)
[![Release](https://github.com/galaxyproject/galaxy-k8s-boot/actions/workflows/release.yaml/badge.svg)](https://github.com/galaxyproject/galaxy-k8s-boot/actions/workflows/release.yaml)
```

### 6.2 Version Dashboard Workflow

Create a workflow that generates a version status dashboard and posts it to Slack weekly.

**File**: `.github/workflows/version-dashboard.yaml` (in galaxy-k8s-boot or a central repo)

```yaml
name: Version Dashboard
on:
  schedule:
    - cron: '0 9 * * 1'  # Every Monday at 9am UTC
  workflow_dispatch: {}

jobs:
  dashboard:
    runs-on: ubuntu-latest
    steps:
      - name: Fetch versions
        id: versions
        run: |
          # Galaxy Helm
          HELM_VERSION=$(curl -s https://api.github.com/repos/galaxyproject/galaxy-helm/releases/latest | jq -r '.tag_name')
          HELM_CHART=$(curl -s https://raw.githubusercontent.com/galaxyproject/galaxy-helm/master/galaxy/Chart.yaml | grep '^version:' | awk '{print $2}')
          HELM_APP=$(curl -s https://raw.githubusercontent.com/galaxyproject/galaxy-helm/master/galaxy/Chart.yaml | grep '^appVersion:' | awk '{print $2}' | tr -d '"')

          # Galaxy Helm Deps
          DEPS_VERSION=$(curl -s https://api.github.com/repos/galaxyproject/galaxy-helm-deps/releases/latest | jq -r '.tag_name')
          DEPS_CHART=$(curl -s https://raw.githubusercontent.com/galaxyproject/galaxy-helm-deps/master/galaxy-deps/Chart.yaml | grep '^version:' | awk '{print $2}')

          # Galaxy K8S Boot
          BOOT_VERSION=$(curl -s https://api.github.com/repos/galaxyproject/galaxy-k8s-boot/releases/latest | jq -r '.tag_name')
          BOOT_HELM=$(curl -s https://raw.githubusercontent.com/galaxyproject/galaxy-k8s-boot/master/roles/galaxy_k8s_deployment/defaults/main.yml | grep 'galaxy_chart_version:' | awk '{print $2}' | tr -d '"')
          BOOT_DEPS=$(curl -s https://raw.githubusercontent.com/galaxyproject/galaxy-k8s-boot/master/roles/galaxy_k8s_deployment/defaults/main.yml | grep 'galaxy_deps_version:' | awk '{print $2}' | tr -d '"')

          # Check for mismatches
          HELM_MISMATCH=""
          DEPS_MISMATCH=""
          if [ "$HELM_CHART" != "$BOOT_HELM" ]; then
            HELM_MISMATCH=":warning: Mismatch!"
          fi
          if [ "$DEPS_CHART" != "$BOOT_DEPS" ]; then
            DEPS_MISMATCH=":warning: Mismatch!"
          fi

          # Save outputs
          echo "helm_version=$HELM_VERSION" >> $GITHUB_OUTPUT
          echo "helm_chart=$HELM_CHART" >> $GITHUB_OUTPUT
          echo "helm_app=$HELM_APP" >> $GITHUB_OUTPUT
          echo "deps_version=$DEPS_VERSION" >> $GITHUB_OUTPUT
          echo "deps_chart=$DEPS_CHART" >> $GITHUB_OUTPUT
          echo "boot_version=$BOOT_VERSION" >> $GITHUB_OUTPUT
          echo "boot_helm=$BOOT_HELM" >> $GITHUB_OUTPUT
          echo "boot_deps=$BOOT_DEPS" >> $GITHUB_OUTPUT
          echo "helm_mismatch=$HELM_MISMATCH" >> $GITHUB_OUTPUT
          echo "deps_mismatch=$DEPS_MISMATCH" >> $GITHUB_OUTPUT

      - name: Post to Slack
        uses: slackapi/slack-github-action@v1.26.0
        with:
          payload: |
            {
              "blocks": [
                {
                  "type": "header",
                  "text": {
                    "type": "plain_text",
                    "text": "Galaxy K8S Version Dashboard"
                  }
                },
                {
                  "type": "section",
                  "fields": [
                    {"type": "mrkdwn", "text": "*galaxy-helm*\nRelease: `${{ steps.versions.outputs.helm_version }}`\nChart: `${{ steps.versions.outputs.helm_chart }}`\nGalaxy: `${{ steps.versions.outputs.helm_app }}`"},
                    {"type": "mrkdwn", "text": "*galaxy-helm-deps*\nRelease: `${{ steps.versions.outputs.deps_version }}`\nChart: `${{ steps.versions.outputs.deps_chart }}`"}
                  ]
                },
                {
                  "type": "section",
                  "fields": [
                    {"type": "mrkdwn", "text": "*galaxy-k8s-boot*\nRelease: `${{ steps.versions.outputs.boot_version }}`\ngalaxy-helm: `${{ steps.versions.outputs.boot_helm }}` ${{ steps.versions.outputs.helm_mismatch }}\ngalaxy-deps: `${{ steps.versions.outputs.boot_deps }}` ${{ steps.versions.outputs.deps_mismatch }}"}
                  ]
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK

      - name: Create issue on mismatch
        if: steps.versions.outputs.helm_mismatch != '' || steps.versions.outputs.deps_mismatch != ''
        uses: peter-evans/create-issue-from-file@v5
        with:
          title: "Version mismatch detected in galaxy-k8s-boot"
          content-filepath: /dev/stdin
          labels: dependencies,automated
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 6.3 Static Dashboard Page (Optional)

Create a simple HTML dashboard that can be hosted on GitHub Pages:

**File**: `docs/dashboard.html`

```html
<!DOCTYPE html>
<html>
<head>
    <title>Galaxy K8S Version Dashboard</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 40px; }
        .card { border: 1px solid #ddd; border-radius: 8px; padding: 20px; margin: 10px; display: inline-block; min-width: 250px; }
        .card h3 { margin-top: 0; }
        .version { font-size: 24px; font-weight: bold; color: #0366d6; }
        .label { color: #666; font-size: 12px; }
        .match { color: #22863a; }
        .mismatch { color: #cb2431; }
        #loading { color: #666; }
    </style>
</head>
<body>
    <h1>Galaxy K8S Version Dashboard</h1>
    <p id="loading">Loading versions...</p>
    <div id="dashboard"></div>

    <script>
        async function fetchVersions() {
            const repos = {
                'galaxy-helm': { chart: 'galaxy/Chart.yaml', type: 'helm' },
                'galaxy-helm-deps': { chart: 'galaxy-deps/Chart.yaml', type: 'helm' },
                'galaxy-k8s-boot': { version: 'VERSION', defaults: 'roles/galaxy_k8s_deployment/defaults/main.yml' }
            };

            const dashboard = document.getElementById('dashboard');
            document.getElementById('loading').style.display = 'none';

            for (const [repo, config] of Object.entries(repos)) {
                const card = document.createElement('div');
                card.className = 'card';

                // Fetch release
                const releaseRes = await fetch(`https://api.github.com/repos/galaxyproject/${repo}/releases/latest`);
                const release = await releaseRes.json();

                let html = `<h3>${repo}</h3>`;
                html += `<div class="label">Latest Release</div>`;
                html += `<div class="version">${release.tag_name || 'N/A'}</div>`;

                card.innerHTML = html;
                dashboard.appendChild(card);
            }
        }

        fetchVersions();
    </script>
</body>
</html>
```
