#!/usr/bin/env bash

# Delete existing rulesets
for repo in test-helm-chart test-helm-deps test-ansible-playbook; do
	for id in $(gh api repos/ksuderman/${repo}/rulesets --jq '.[].id'); do
		echo "Deleting ruleset $id in repository ${repo}."
		gh api -X DELETE repos/ksuderman/${repo}/rulesets/$id
	done
done
