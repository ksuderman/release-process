# Refactoring the Galaxy Helm Release Process

The purpose of this repository is to coordinate the refatoring of the release process for the following repositories:

- [Galaxy Helm](https://github.com/galaxyproject/galaxy-helm) chart.
- [Galaxy Deps Helm](https://github.com/galaxyproject/galaxy-helm-deps) chart.
- [Galaxy K8S Boot](https://github.com/galaxyproject/galaxy-k8s-boot) playbook.
- [Cloudve Helm Repository](https://github.com/CloudVE/helm-charts).

I haven't included the Galaxy Kubeman chart, but we could if we wanted.

The goal is to make the process consistent across all repositories and automate the process as much as possible.  Ideally all we will need to do is approve pull requests and let the magic happen.  This requires a consistent repository layout and process even if it does not make much sense for the particular repository, e.g., we probably won't update the Galaxy dependencies very often, but by using the same release process we don't have to remember respository specific procedures.

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
**A**: Not really, but having all repositories be consistent simplifies state management in the workflows and we don't need to remember different processes depending on the repository.



