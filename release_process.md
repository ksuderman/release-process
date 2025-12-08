# Release Process

This is a planning document for defining and coordinating the release process for the Galaxy Helm chart and related repositories.

## Repositories

1. The main Galaxy repository is https://github.com/galaxyproject/galaxy which has been cloned to /Users/suderman/Workspaces/JHU/galaxy-upstream.  We do not manage this repository or perform releases there, but whenever a new Galaxy release is tagged on GitHub the `build_container_image.yaml` will create a pull request to update the new Galaxy version in the Galaxy Helm repository.
2. The Galaxy Helm chart repository is https://github.com/galaxyproject/galaxy-helm and contains the Helm chart that is used to deploy Galaxy to Kubernetes clusters.  The repository has been cloned into  /Users/suderman/Workspaces/JHU/galaxy-helm.
3. The Galaxy Dependencies Helm chart repository is https://github.com/galaxyproject/galaxy-helm-deps and has been cloned into /Users/suderman/Workspaces/JHU/galaxy-helm-deps.
4. The Galaxy K8S Boot project consists of an Ansible Playbook that used the Galaxy Helm chart to deploy Galaxy to an RKE2 cluster.  The Git repository is https://github.com/galaxyproject/galaxy-k8s-boot and has been cloned to /Users/suderman/Workspaces/JHU/galaxy-k8s-boot. The repository contains scripts to launch a GCP VM and run the playbook via a cloud init script.
5. Helm charts are deployed to our Helm repository https://raw.githubusercontent.com/CloudVE/helm-charts/master/ which is served from the Git repository https://github.com/CloudVE/helm-charts. The Git repository has been cloned to /Users/suderman/Workspaces/JHU/cloudve-helm-charts.

## Versioning

All projects, except the Cloudve Helm chart repository, use semantic versioning.  The version for the Galaxy Helm and Galaxy Dependencies projects is stored in the Chart.yaml file. Rhe Galaxy K8S Boot repository contains a plain text file named VERSION that contains the current version number.  The version should be bumped every time a new release is performed.

## Release Process

We do not manage releases for the Galaxy project itself, but we do for the others.

The development and release process is similar for all repositories. New features are introduced by creating pull requests that target the `dev` branch.  All new pull requests to the `galaxy-helm`, `galaxy-helm-deps`, and `galaxy-k8s-boot` repositories should trigger the `smoke-test` workflow.  Currently, only the `galaxy-k8s-boot` repository has a smoke test, but that test can be re-used  for the other repositories.

The release process is started when a repository owner creates a pull request from the `dev` branch to the `master` branch.  The pull request can not be merged into `master` unless it contains a label of `major`, `minor`, or `patch` that is used to determine how the version number should be incremented. No other pull requests that target the master branch are allowed.

When another repository owner approves the pull request the following steps should take place:
1. The version number is incremented according to the label supplied.
2. The smoke test is run.  More tests will be added depending on the repository.
3. A GitHub `tag` is created. The tag name should be a lowercase letter v followed by the version number. For example, `v1.2.3`
4. A GitHub release is created from the tag. The release name should be the string "release_" followed by the version number. For example, `release_1.2.3`
5. The `master` branch should be merged back into the `dev` branch.

Some projects require additional steps.

### Galaxy Helm Chart

1. The https://github.com/CloudVE/helm-charts repository is updated to include the new version of the Galaxy Helm chart.
2. A pull request is opened in the Galaxy K8S Boot repository to update the default value of the GALAXY_CHART_VERSION variable in the `launch_vm.sh` script, and the galaxy_chart_version variable in the `roles/galaxy_k8s_deployment/defaults/main.yml` file. The pull request should target the `dev` branch.  

### Galaxy Dependencies

1. A pull request is opened in the Galaxy K8S Boot repository to update the default value of the GALAXY_DEPS_VERSION variable in the `launch_vm.sh` script, and the galaxy_deps_version variable in the `roles/galaxy_k8s_deployment/defaults/main.yml` file. The pull request should target the `dev` branch.  

