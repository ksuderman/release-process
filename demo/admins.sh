#!/usr/bin/env bash

ADMINS="afgane nuwang"
REPOS="test-helm-chart" "test-helm-deps" "test-ansible-playbook" "test-helm-repo")

for repo in "${REPOS[@]}" ; do
	for admin in $ADMINS ; do
		gh api -X PUT repos/ksuderman/$repo/collaborators/$admin -f permission="admin"
	done
done
