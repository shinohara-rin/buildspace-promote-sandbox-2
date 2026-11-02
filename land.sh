#!/bin/bash
# Land one change in the sandbox the way a real one lands: a pull request,
# optionally labelled, squash-merged into main, which runs Stage.
#
#   ./land.sh "fix: first change"
#   ./land.sh "feat: risky change" min-staging-age:30m
#   MERGE=1 ./land.sh "fix: two steps"   # two commits, merged with a merge commit
set -euo pipefail

TITLE=$1
LABEL=${2:-}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" remote get-url origin | sed -E 's#.*github.com[/:]##; s#\.git$##')
BRANCH="change/$(date +%s)"

git -C "$HERE" switch -q main
git -C "$HERE" pull -q --ff-only
git -C "$HERE" switch -q -c "$BRANCH"
echo "$(date -u +%FT%TZ) $TITLE" >> "$HERE/CHANGES"
git -C "$HERE" add CHANGES
git -C "$HERE" commit -q -m "$TITLE"
if [[ -n "${MERGE:-}" ]]; then
  echo "$(date -u +%FT%TZ) $TITLE, second step" >> "$HERE/CHANGES"
  git -C "$HERE" commit -q -am "$TITLE, second step"
fi
git -C "$HERE" push -q -u origin "$BRANCH"
URL=$(gh pr create --repo "$REPO" --head "$BRANCH" --title "$TITLE" --body "Sandbox change for ENG-4678")
[[ -n "$LABEL" ]] && gh pr edit "$URL" --add-label "$LABEL"
gh pr merge "$URL" $([[ -n "${MERGE:-}" ]] && echo --merge || echo --squash) --delete-branch
git -C "$HERE" switch -q main
git -C "$HERE" pull -q --ff-only
echo "Landed $URL; Stage is running: gh run list --repo $REPO --workflow stage.yml --limit 1"
