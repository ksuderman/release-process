#!/usr/bin/env bash
set -eu

ksuderman=$(gh api users/ksuderman | jq .id)
enis=$(gh api users/afgane | jq .id)
nuwan=$(gh api users/nuwang | jq .id)

cat << EOF > /tmp/reviewers.json
{
	"reviewers" : [
		{"type": "User", "id": $ksuderman},
		{"type": "User", "id": $enis},
		{"type": "User", "id": $nuwan}
	]
}
EOF
exit

for repo in test-helm-chart test-helm-deps test-ansible-playbook ; do
  gh api -X PUT -H 'Content-type: application/json' --input /tmp/reviewers.json repos/ksuderman/$repo/environments/release
done
