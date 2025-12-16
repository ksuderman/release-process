# Test Ansible Playbook

A demo Ansible playbook for testing the release automation process.

![Version](https://img.shields.io/github/v/release/GITHUB_USER/test-ansible-playbook?label=version)
![Test Chart](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/GITHUB_USER/test-ansible-playbook/master/roles/demo/defaults/main.yml&query=$.test_chart_version&label=test-chart)
![Test Deps](https://img.shields.io/badge/dynamic/yaml?url=https://raw.githubusercontent.com/GITHUB_USER/test-ansible-playbook/master/roles/demo/defaults/main.yml&query=$.test_deps_version&label=test-deps)

## Overview

This repository demonstrates:
- PR validation workflow
- Automated version bumping (VERSION file)
- Release creation with auto-generated notes
- Receiving automated dependency update PRs from upstream charts
