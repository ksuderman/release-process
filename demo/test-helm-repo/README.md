# Test Helm Repository

A demo Helm chart repository for testing the release automation process.

## Usage

```bash
helm repo add test-repo https://raw.githubusercontent.com/GITHUB_USER/test-helm-repo/master/
helm repo update
```

## Overview

This repository:
- Receives packaged Helm charts from test-helm-chart and test-helm-deps
- Maintains an index.yaml for Helm repository functionality
- Is updated automatically by release workflows
