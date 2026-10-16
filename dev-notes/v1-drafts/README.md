# v1 drafts (2026-10-16)

Files for the v1 setup of this repository, drafted while the user was
away — **nothing here is wired in or applied.** Plan:
[../v1-planning.md](../v1-planning.md).

| File | Goes to | Applied by |
|---|---|---|
| `ruleset-main.json` | governance repo (ruleset on `main`) | user |
| `ruleset-dev.json` | governance repo (ruleset on `dev`) | user |
| `ruleset-release-tags.json` | governance repo (`v*` tags) | user |
| `self-pr-checks.yml` | `.github/workflows/pr-checks.yml` | at the branch-model switch |
| `self-release.yml` + `self.releaserc.json` | `.github/workflows/release.yml` + release config | at v1 |
| `governance.yml` | governance repo (structure only) | user |

## Rulesets

GitHub's ruleset export format, importable in the repository settings
(Rules → Rulesets → Import) or through the API.

- **main:** no deletion, no force push, linear history, signed commits
  (the user wants signing), PR required with 0 approvals (one
  maintainer; the PR itself is the gate), merge commits only (keeps the
  dev commits for semantic-release). Required checks: the three CI jobs,
  the head-branch check (only `dev` may merge) and the smoke test.
- **dev:** the same without linear history and without the head-branch
  and smoke checks; squash allowed; plus the commit-message check.
  `do_not_enforce_on_create` so the branch can be created.
- **release tags:** only the release App may create, move or delete
  `v*` tags. `actor_id` 0 is a placeholder for the App's ID.

Open for the user:
- signed commits on `main` also need the merge commit signed — GitHub
  signs merges made in its UI; a merge by an App or a local merge needs
  a signing key there;
- whether the smoke test is required from the start (it needs its
  federation rule first);
- check names are those of `ci.yml` and of the reusable workflows
  called from `self-pr-checks.yml` (`<job id> / <job>`); they change if
  those jobs are renamed.

## Release of this repository

semantic-release on `main` with `v`-prefixed tags (`v1.0.0`), the GitHub
release published directly (not a draft — nothing to look over for a
workflow repository), and the major tag `v1` moved by `successCmd`.
No commit, no CHANGELOG file (the release notes are on GitHub).
`package-release.yml` stays the R-package release; see the comment in
`self-release.yml` for the config file clash at the repository root.

Before the first real release: delete the old unused `v1` tag
(`8d11341`, CLAUDE.md "Versioning").

## Governance YAML

Structure for the reconcile script of the plan's section 5, with made-up
names: workspaces, one service account per owner, one federation rule
per owner × workflow (plus this repository's smoke test on PR refs),
and per repository the secrets with where each value comes from. The
script and the Admin API calls aren't drafted — they live in the private
repo and need the `org:admin` token setup first.
