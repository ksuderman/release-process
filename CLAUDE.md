# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a planning and coordination repository for refactoring the release process across the Galaxy Kubernetes ecosystem. It contains design documents and implementation plans but no executable code.

### Related Repositories

| Repository | Location | Purpose |
|------------|----------|---------|
| galaxy-helm | /Users/suderman/Workspaces/JHU/galaxy-helm | Main Galaxy Helm chart |
| galaxy-helm-deps | /Users/suderman/Workspaces/JHU/galaxy-helm-deps | Galaxy dependencies Helm chart |
| galaxy-k8s-boot | /Users/suderman/Workspaces/JHU/galaxy-k8s-boot | Ansible playbook for RKE2 deployment |
| galaxykubeman-helm | /Users/suderman/Workspaces/JHU/galaxykubeman-helm | Galaxy Kubeman Helm chart (depends on galaxy-helm) |
| galaxy-cvmfs-csi-helm | /Users/suderman/Workspaces/JHU/galaxy-cvmfs-csi-helm | CVMFS CSI Helm chart (dependency of galaxy-helm-deps) |
| galaxy-docker-k8s | /Users/suderman/Workspaces/JHU/galaxy-docker-k8s | Ansible playbook for Galaxy Docker image builds |
| galaxy | /Users/suderman/Workspaces/JHU/galaxy | Upstream Galaxy repository |
| cloudve-helm-charts | /Users/suderman/Workspaces/JHU/cloudve-helm-charts | Helm chart repository destination |

## Key Documents

- `release_process.md` - Design specification for the release workflow
- `release_automation_implementation.md` - Implementation plan with GitHub Actions workflows

## Release Process Architecture

### Branch Strategy
- All repos use `master` and `dev` branches
- Features go to `dev` via PRs
- Releases happen by PR from `dev` to `master`
- PRs to master require `major`, `minor`, or `patch` label

### Version Locations
- galaxy-helm: `galaxy/Chart.yaml`
- galaxy-helm-deps: `galaxy-deps/Chart.yaml`
- galaxy-k8s-boot: `VERSION` file (plain text)
- galaxykubeman-helm: `galaxykubeman/Chart.yaml`
- galaxy-cvmfs-csi-helm: `galaxy-cvmfs-csi/Chart.yaml`
- galaxy-docker-k8s: Git tags only (e.g., `v4.2.0`)

### Release Cascade
1. Galaxy releases trigger galaxy-helm appVersion update
2. galaxy-helm releases trigger CloudVE/helm-charts update + galaxy-k8s-boot PR
3. galaxy-helm-deps releases trigger galaxy-k8s-boot PR
4. galaxy-cvmfs-csi-helm releases trigger galaxy-helm-deps PR (to update dependency version)
5. galaxykubeman-helm releases trigger CloudVE/helm-charts update (no downstream)
6. galaxy-docker-k8s releases trigger galaxy (upstream) PR to update `.k8s_ci.Dockerfile`

### Key Files Updated on Release

**galaxy-k8s-boot** (updated by galaxy-helm and galaxy-helm-deps releases):
- `bin/launch_vm.sh`: `GALAXY_CHART_VERSION`, `GALAXY_DEPS_VERSION`
- `roles/galaxy_k8s_deployment/defaults/main.yml`: `galaxy_chart_version`, `galaxy_deps_version`

**galaxy (upstream)** (updated by galaxy-docker-k8s releases):
- `.k8s_ci.Dockerfile`: `GALAXY_PLAYBOOK_BRANCH` ARG

**galaxy-helm-deps** (updated by galaxy-cvmfs-csi-helm releases):
- `galaxy-deps/Chart.yaml`: `galaxy-cvmfs-csi` dependency version

## Deprecated Components

Do NOT use:
- `packaging.yml` in galaxy-helm, galaxykubeman-helm, galaxy-cvmfs-csi-helm
- `cloudve/helm-ci@master` GitHub Action

## Conventions

- Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages
- Test against Kubernetes versions 1.28-1.32
- Smoke tests: K3S for helm repos, GCP VMs for galaxy-k8s-boot
