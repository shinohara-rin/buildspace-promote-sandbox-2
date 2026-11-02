# buildspace-promote-sandbox

Test bed for ENG-4678: buildspace's swift-promote waits until every change has
run on staging for a minimum age. This repository stages and promotes a package
that does nothing, through the buildspace branch
`cw/feat/eng-4678-promote-minimum-staging-age`, so the real 19 callers (pinned
to `422dfd1`) never see it.

Nothing installs this package: GitGate installs only the repositories in
macrocosm-astrolabe's `GitGateRegistry.swift`, and `promote.yml` sets no
`jamf-url`. No staging host is involved, so no #team-macrocosm claim is needed.

## Setup

`./setup.sh` does everything below; read it first, since every step writes to GitHub.

1. Push the buildspace branch somewhere the sandbox can call it. You have read
   access to `photon-hq/buildspace` only, so by default this forks it to your
   account and pushes the branch there.
2. Point `stage.yml` and `promote.yml` at that branch.
3. Create the sandbox repo: `OWNER=photon-hq ./setup.sh` makes it internal
   under the org, like the real callers; plain `./setup.sh` makes it public
   under your account. A private repo under a personal account can't promote:
   on GitHub Free, Pro and Team, environment required reviewers exist only
   for public repositories. Under the org, the org's Actions policy must also
   allow calling a workflow from your fork; if Stage fails with a "not
   allowed" error, that's the reason.
4. Create the `production` environment with you as required reviewer.
5. Create the `min-staging-age:10m|15m|30m` labels.
6. Push `main`, which runs Stage and publishes the first staging build.

`./land.sh "<title>" [label]` lands a change as a squash-merged PR, which stages a new build.

Promote runs from Actions → Promote → Run workflow on `main`, or
`gh workflow run promote.yml -f minimum-staging-age=5m`. The age check runs in the
`resolve` job; read its job summary.

## Test plan

`minimum-staging-age` defaults to `5m` here. Times are from each staging release's
`published_at`.

| # | Steps | Expect |
|---|---|---|
| 1 | Right after setup's first Stage finishes, promote | `resolve` fails: `has not run on staging long enough`, the summary table shows the change waiting about 5m |
| 2 | Wait 5m after the staging release, promote | `resolve` passes and the summary shows `ready`; `publish` waits for your approval; approve; `v0.1.0` is released |
| 3 | `./land.sh "fix: a" min-staging-age:15m`, wait for Stage, then `./land.sh "fix: b"`; promote once b has run 5m but a has not reached 15m | Fails on `fix: a` only: `needs 15m (min-staging-age:15m)`; b is `ready` |
| 4 | Same as 3, promote once a has 15m | Passes; both rows `ready` |
| 5 | `./land.sh "fix: c" min-staging-age:10m`; promote right away with `-f minimum-staging-age=30m` | c needs 30m: a label never lowers the default |
| 6 | `./land.sh "fix: d"`; promote right away with `-f skip-minimum-age-reason="sandbox hotfix"` | `resolve` passes and the summary says `Promoted before its minimum staging age: sandbox hotfix`; approve; the release notes carry the same line |
| 7 | Land e, then f; promote `-f staging-version=<e's staging version>` after e has 5m | Only the changes up to e are listed; f is not |
| 8 | Land g, cancel its Stage run, land h; promote after h has 5m | g's clock starts at h's staging release, not g's merge |
| 9 | Promote after a promotion with nothing new | `resolve` reports the build already released; no age check |
| 10 | Remove `pull-requests: read` from `promote.yml` on a branch, then promote | Fails: `grant the promote job pull-requests: read` |

Also check that `gh attestation verify` in `resolve` accepts a stage run from
the fork branch (`--signer-workflow <owner>/buildspace/.github/workflows/swift-stage.yml`).
The unit tests fake it, so only this sandbox shows whether the signer's ref matters.

## Cleanup

`gh repo delete <owner>/buildspace-promote-sandbox` and, if setup made one, the
`<you>/buildspace` fork.
