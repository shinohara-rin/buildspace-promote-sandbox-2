#!/bin/bash
# One-time setup of the ENG-4678 promote sandbox. Every step writes to GitHub,
# so read it before running. Re-running skips what already exists.
#
#   OWNER=photon-hq ./setup.sh # sandbox internal under photon-hq, like the real callers
#   ./setup.sh                 # sandbox public under your account
#
# A private repository under a personal account cannot work: on GitHub Free,
# Pro and Team, environment required reviewers (which promotion insists on)
# exist only for public repositories.
#
# The buildspace branch goes to your fork (buildspace is public and you can only
# read it) unless BUILDSPACE_REPO=photon-hq/buildspace and you can push there.
#
# Needs: gh logged in, the buildspace worktree with the branch committed.
set -euo pipefail

ME=$(gh api user --jq .login)
OWNER=${OWNER:-$ME}
SANDBOX=${SANDBOX:-buildspace-promote-sandbox}
BRANCH=cw/feat/eng-4678-promote-minimum-staging-age
BUILDSPACE_DIR=${BUILDSPACE_DIR:-$HOME/Desktop/photon/buildspace/.claude/worktrees/eng-4678}
BUILDSPACE_REPO=${BUILDSPACE_REPO:-$ME/buildspace}
# The workflows call this ref; pin a commit sha so the code cannot change mid-test.
BUILDSPACE_REF=${BUILDSPACE_REF:-$BRANCH}
HERE=$(cd "$(dirname "$0")" && pwd)

# 1. The buildspace branch, where the sandbox can call it.
if [[ "$BUILDSPACE_REPO" == "$ME/buildspace" ]]; then
  gh repo view "$BUILDSPACE_REPO" >/dev/null 2>&1 || gh repo fork photon-hq/buildspace --clone=false --default-branch-only
fi
git -C "$BUILDSPACE_DIR" push "https://github.com/$BUILDSPACE_REPO.git" "$BRANCH:$BRANCH"

# 2. Point both workflows at that branch.
for f in "$HERE/.github/workflows/stage.yml" "$HERE/.github/workflows/promote.yml"; do
  sed -i '' -E "s#uses: [^/]+/buildspace/\.github/workflows/(swift-(stage|promote)\.yml)@.*#uses: $BUILDSPACE_REPO/.github/workflows/\1@$BUILDSPACE_REF#" "$f"
done

# 3. The sandbox repository: internal under the org, as macrocosm-astrolabe is,
#    so attestations go through the same GitHub Sigstore instance as the real
#    callers'; public under a personal account (see the header).
VISIBILITY=--public
[[ "$OWNER" != "$ME" ]] && VISIBILITY=--internal
if ! gh repo view "$OWNER/$SANDBOX" >/dev/null 2>&1; then
  gh repo create "$OWNER/$SANDBOX" "$VISIBILITY" --description "ENG-4678: test bed for buildspace's minimum staging age; nothing installs it"
fi
if [[ ! -d "$HERE/.git" ]]; then
  git -C "$HERE" init -q -b main
  git -C "$HERE" remote add origin "https://github.com/$OWNER/$SANDBOX.git"
fi
git -C "$HERE" add -A
git -C "$HERE" diff --cached --quiet || git -C "$HERE" commit -q -m "feat: promote sandbox for the minimum staging age (ENG-4678)"

# 4. The production environment, with you as its required reviewer. Promotion
#    refuses to run without a reviewer.
REVIEWER_ID=$(gh api user --jq .id)
gh api -X PUT "repos/$OWNER/$SANDBOX/environments/production" \
  -F "reviewers[][type]=User" -F "reviewers[][id]=$REVIEWER_ID" >/dev/null

# 5. Labels the test cases use.
for age in 10m 15m 30m; do
  gh label create "min-staging-age:$age" --repo "$OWNER/$SANDBOX" --color FBCA04 \
    --description "Hold this change on staging for at least $age before promotion" 2>/dev/null || true
done

# 6. First push: runs Stage, which publishes the first staging build.
git -C "$HERE" push -u origin main
echo "Sandbox: https://github.com/$OWNER/$SANDBOX (buildspace: $BUILDSPACE_REPO@$BUILDSPACE_REF)"
