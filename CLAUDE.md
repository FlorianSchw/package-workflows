# Project: package-workflows

## WHAT THIS REPO IS
Public, shared GitHub Actions repo used by repos across three GitHub accounts
(personal `FlorianSchw`, and two orgs — `nfdi4health` is one). Holds reusable
`workflow_call` workflows so CI/release/doc-assist logic is written once and
called from thin per-repo "caller" workflow files, rather than copy-pasted
per repo.

**Critical operational fact:** changes here only take effect for callers once
pushed to `main` (or whichever ref a caller pins to). A caller referencing
`@main` picks up the latest commit on next run — there is no separate "deploy"
step. When debugging a caller's behavior, always confirm which commit the
workflow run actually used before assuming a fix did or didn't work; a run
can be stale relative to what's currently on `main` if it started before a
push landed.

**Test bed:** `nfdi4health/dsSupportClient` (a DataSHIELD client package) is
the live caller used to validate changes before wider rollout.

## LAYOUT

- `.github/workflows/` — reusable workflows:
  - `R-CMD-Check.yml` — R CMD check matrix + optional codecov upload.
    Inputs: `os-list`, `r-version-list` (JSON array strings; default
    release + oldrel-1/2), `run-codecov`, `extra-apt-packages`,
    `extra-r-packages` (plain names, `any::` added internally).
  - `package-release.yml` — semantic-release. Uses a caller-root
    `.releaserc.json` if present, else this repo's `.releaserc.json`
    fetched at `config-ref` (default: tag `v1`). Pushes with the
    `resolve-push-token` App token → `commit-push-pat` → `GITHUB_TOKEN`.
  - `trigger-release-publish.yml` — sends a `repository_dispatch`
    (`event_type: release-publish`) to the caller repo; the caller's own
    workflow listens for it and runs the release.
  - `merge-pull-request.yml` — merges a PR via `gh pr merge`. No PAT needed
    (`release` runs via `needs:`, not a fresh `push` event).
  - `require-head-branch.yml` — fails a PR whose head branch isn't
    `allowed-head` (e.g. only `dev` may merge into `main`).
  - `create-issue.yml` — opens an issue on check failure from
    `.github/pr-issue-template.md`.
  - `commitlint.yml` — conventional-commit lint using
    `config/commitlint-config.mjs`.
  - `check-description-authors.yml` — resolves each PR commit's author to
    their GitHub profile name and suggests adding missing ones to
    `DESCRIPTION` (`aut`) via a `bot-suggest/authors` sub-PR. Bots are
    skipped per `config/bot-authors.json` (overridable, see
    `resolve_shared_path()` below).
  - `roxygen-suggest.yml`, `test-coverage-suggest.yml` — LLM-assisted
    suggestion workflows; see below.
  - `cleanup-suggestion-branch.yml` — on PR close, deletes a `bot-suggest/*`
    head branch unless another open PR still uses it.
- Branch-protection rulesets (formerly `rulesets/` + `apply-ruleset.yml`)
  now live in a separate private repo.
- `.github/actions/` — composite actions: `anthropic-token` (suggestion
  workflows), `resolve-push-token` (also `package-release.yml`),
  `commit-updated-files` (also `check-description-authors.yml`).
- `R/` — entry scripts `suggest_roxygen.R`, `suggest_tests.R`,
  `check_description_authors.R` (env/config wiring + main loop only) and
  `R/functions/` (all logic, one function per file, loaded in bulk via
  `purrr::walk()`). No R inlined in workflow YAML.
- `config/`, `prompts/`, `config.yml` — guidance, prompt templates and
  Claude call settings for the suggestion workflows.
- `docs/` — per-workflow design notes and status.

## SUGGESTION WORKFLOWS — shared mechanics

Details per workflow: [docs/roxygen-suggest.md](docs/roxygen-suggest.md),
[docs/test-coverage-suggest.md](docs/test-coverage-suggest.md).

- **Auth: WIF, no static API key.** The `anthropic-token` action exchanges
  the job's GitHub OIDC token for a short-lived Anthropic token. Nothing
  is hard-coded: callers pass `anthropic-organization-id`,
  `anthropic-service-account-id` and `anthropic-federation-rule-id` as
  required secrets, so any repo can use its own Anthropic org and pay for
  its own usage. Console layout: one **workspace per workflow type**
  (docs, tests), one **service account per repo** (member of both
  workspaces; the Cost page groups by service account), one **federation
  rule per repo × workflow** (`subject_prefix: repo:<owner>/<repo>:*` plus
  a `claims` matcher on `job_workflow_ref`, targeting the repo's service
  account in that workflow's workspace). Because each workflow needs its
  own rule ID, callers map secrets explicitly — not `secrets: inherit`.
- **Claude settings:** `config.yml`, one `default` profile plus one per
  task (`roxygen-review`, `test-review`, `test-failure-classification`),
  read with `config::get()`. The workflow sets `R_CONFIG_ACTIVE` as an env
  var on the script step. Every Claude call goes through
  `call_claude_tool()` (forced tool call; it sets the tool name from config).
- **Claude returns fields, R assembles the output.** Never trust prompt
  wording where a structural constraint (schema field, `maxItems`, enum)
  is possible.
- **Where shared files come from:** callers get this repo checked out into
  `.shared-workflows/`. `resolve_shared_path("config/x.json")` uses the
  caller's own file at that same relative path if it exists (an override),
  else the `.shared-workflows/` copy.
- **Committing:** scripts write `updated_files.txt`; `commit-updated-files`
  commits exactly those files. `changed` mode: per-file commits on a
  sub-branch `bot-suggest/<kind>/<PR branch with / → ->`, force-pushed and
  opened as a sub-PR *back into the PR branch* — never committed onto it
  directly, so the PR author reviews every suggestion. When the sub-PR is
  newly created and `origin-pr-number` is set, a link comment is posted on
  the originating PR. `all` mode: one commit on a dated sweep branch + PR
  against `dev`. `resolve-push-token` provides an App token when
  configured, so the bot's PRs trigger the caller's required checks
  (`GITHUB_TOKEN`-created ones don't). Merged/closed sub-PR branches are
  removed by `cleanup-suggestion-branch.yml`.

## STILL OPEN

- The suggestion workflows are referenced `@main` by callers; `v1` exists but
  only `package-release.yml` uses it (for its release config). Decide on
  versioning once the suggestion workflows stabilise.
- Federation rules for the other two accounts, before rolling out beyond
  dsSupportClient.
- Not yet confirmed in real CI: `all` mode of both suggestion workflows;
  `test-coverage-suggest.yml` actually generating, running and proposing
  tests (it has run on dsSupportClient PR #18, but nothing was needed).
  `package-release.yml` and
  `merge-pull-request.yml` haven't run since the refactor.
- Shared caching for `R-CMD-Check.yml` — flagged, not started.
