# Refactoring the Galaxy Helm Release Process

The purpose of this repository is to coordinate the refactoring of the release process for the following repositories:

- [Galaxy Helm](https://github.com/galaxyproject/galaxy-helm) chart.
- [Galaxy Deps Helm](https://github.com/galaxyproject/galaxy-helm-deps) chart.
- [Galaxy K8S Boot](https://github.com/galaxyproject/galaxy-k8s-boot) playbook.
- [Galaxy Kubeman Helm](https://github.com/galaxyproject/galaxykubeman-helm) chart.
- [Galaxy CVMFS CSI Helm](https://github.com/CloudVE/galaxy-cvmfs-csi-helm) chart.
- [Galaxy Docker K8S](https://github.com/galaxyproject/galaxy-docker-k8s) playbook.
- [Cloudve Helm Repository](https://github.com/CloudVE/helm-charts).

The goal is to make the process consistent across all repositories and automate the process as much as possible.  Ideally all we will need to do is approve pull requests and let the magic happen.  This requires a consistent repository layout and process even if it does not make much sense for the particular repository, e.g., we probably won't update the Galaxy dependencies very often, but by using the same release process we don't have to remember respository specific procedures.

## Current Versions

### Galaxy Helm Chart

![Version](https://img.shields.io/github/v/release/galaxyproject/galaxy-helm?label=chart%20version)
![Kubernetes](https://img.shields.io/badge/kubernetes-1.28%20--%201.32-blue)
![Galaxy](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/galaxyproject/galaxy-helm/master/galaxy/Chart.yaml&query=$.appVersion&label=galaxy%20version)

[![CI](https://github.com/galaxyproject/galaxy-helm/actions/workflows/test.yaml/badge.svg)](https://github.com/galaxyproject/galaxy-helm/actions/workflows/test.yaml)
[![Release](https://github.com/galaxyproject/galaxy-helm/actions/workflows/packaging.yml/badge.svg)](https://github.com/galaxyproject/galaxy-helm/actions/workflows/release.yaml)

### Galaxy Dependencies Helm Chart

![Version](https://img.shields.io/github/v/release/galaxyproject/galaxy-helm-deps?label=chart%20version)
![Kubernetes](https://img.shields.io/badge/kubernetes-1.28%20--%201.32-blue)

[![CI](https://github.com/galaxyproject/galaxy-helm-deps/actions/workflows/test.yaml/badge.svg)](https://github.com/galaxyproject/galaxy-helm-deps/actions/workflows/test.yaml)
[![Release](https://github.com/galaxyproject/galaxy-helm-deps/actions/workflows/packaging.yml/badge.svg)](https://github.com/galaxyproject/galaxy-helm-deps/actions/workflows/release.yaml)

### Galaxy K8S Boot

![Version](https://img.shields.io/github/v/release/galaxyproject/galaxy-k8s-boot?label=version)
![Galaxy Helm](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/galaxyproject/galaxy-k8s-boot/master/roles/galaxy_k8s_deployment/defaults/main.yml&query=$.galaxy_chart_version&label=galaxy-helm)
![Galaxy Deps](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/galaxyproject/galaxy-k8s-boot/master/roles/galaxy_k8s_deployment/defaults/main.yml&query=$.galaxy_deps_version&label=galaxy-deps)

[![Smoke Test](https://github.com/galaxyproject/galaxy-k8s-boot/actions/workflows/test-galaxy-gce.yml/badge.svg)](https://github.com/galaxyproject/galaxy-k8s-boot/actions/workflows/test-galaxy-gce.yml)<br/>
[![Release](https://github.com/galaxyproject/galaxy-k8s-boot/actions/workflows/release.yaml/badge.svg)](https://github.com/galaxyproject/galaxy-k8s-boot/actions/workflows/release.yaml)

### Galaxy Kubeman Helm Chart

![Version](https://img.shields.io/github/v/release/galaxyproject/galaxykubeman-helm?label=chart%20version)
![Galaxy](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/galaxyproject/galaxykubeman-helm/master/galaxykubeman/Chart.yaml&query=$.appVersion&label=galaxy%20version)

[![Lint](https://github.com/galaxyproject/galaxykubeman-helm/actions/workflows/lint.yaml/badge.svg)](https://github.com/galaxyproject/galaxykubeman-helm/actions/workflows/lint.yaml)

### Galaxy CVMFS CSI Helm Chart

![Version](https://img.shields.io/github/v/release/CloudVE/galaxy-cvmfs-csi-helm?label=chart%20version)
![CVMFS CSI](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/CloudVE/galaxy-cvmfs-csi-helm/master/galaxy-cvmfs-csi/Chart.yaml&query=$.appVersion&label=cvmfs-csi%20version)

### Galaxy Docker K8S

![Version](https://img.shields.io/github/v/release/galaxyproject/galaxy-docker-k8s?label=version)


## Key Concepts

1. All repositories have `master` and `dev` branches.
2. Features are added via pull requests to the `dev` branch.
3. Releases are initiated by creating a pull request from `dev` into `master`
4. Pushing directly into `master` is not allowed. There are ways to bypass this restriction in the case of an ***emergency***.
5. Hopefully we agree to use [Conventional Commits](https://www.conventionalcommits.org/) when feasible to aid the automatic generation of release notes. Conventional commits can also be used to automatically determine if a `major`, `minor`, of `patch` release is being performed rather than using labels on the pull request.
6. The only exception is the Cloudve Helm repository where a `dev` branch makes little to no sense.  However, the only pull requests here should be from automated workflows in the other repositories.

## Documents

The [release_process.md](./release_process.md) file contains the design specification I gave to Claude.ai/code and [release_automation_implementaion.md](./release_automation_implementation.md) contains the implementation plan Claude came up with.  The idea is to discuss and iterate over the design and implementation until we are happy and then have Claude do most of the heavy lifting.

## FAQ

**Q**: Do we really need dev branches in each repository?<br/>
**A**: Not really, but having all repositories be consistent simplifies state management in the workflows and we don't need to remember different processes for each repository.



