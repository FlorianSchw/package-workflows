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
    fetched at `config-ref` (default: `main`). Pushes with the
    `resolve-push-token` App token → `commit-push-pat` → `GITHUB_TOKEN`.
    The shared config drafts the release and turns off the GitHub
    plugin's comments, labels and failure issue, so the App needs no
    Issues permission.
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
- `config/`, `prompts/` — guidance, prompt templates and
  Claude call settings for the suggestion workflows.
- `dev-notes/` — internal design notes and status per suggestion workflow
  (not published).
- `docs/` — Quarto site, published to GitHub Pages by `publish-docs.yml`
  (the only non-reusable workflow). One page per workflow, grouped in the
  sidebar via `docs/_quarto.yml`. Inputs/secrets/permissions tables are
  generated from the workflow YAML by `docs/_shortcodes/workflow.lua`
  (`wf-inputs`, `wf-secrets`, `wf-permissions`); `example` includes a file
  from `examples/` — generic caller files, `@main`. Adding or changing a
  workflow: update its example and page prose too; the tables follow
  automatically. Preview with `quarto preview docs`.

## SUGGESTION WORKFLOWS — shared mechanics

Details per workflow: [dev-notes/roxygen-suggest.md](dev-notes/roxygen-suggest.md),
[dev-notes/test-coverage-suggest.md](dev-notes/test-coverage-suggest.md).

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
- **Claude settings:** `config/claude.yml` (not a root `config.yml`: R
  packages using the `config` package often have one, which would override
  it), one `default` profile plus one per
  task (`roxygen-review`, `test-review`, `test-failure-classification`),
  read with `config::get()`. The workflow sets `R_CONFIG_ACTIVE` as an env
  var on the script step. Every Claude call goes through
  `call_claude_tool()` (forced tool call; it sets the tool name from config).
- **Claude returns fields, R assembles the output.** Never trust prompt
  wording where a structural constraint (schema field, `maxItems`, enum)
  is possible.
- **Threshold for what gets proposed:** Claude states a reason per change
  from a fixed enum (`suggestion_reasons()`), R keeps only the
  `accept_reasons` of `config/claude.yml` and adds mechanical filters.
  A revisable decision, recorded in
  [dev-notes/suggestion-thresholds.md](dev-notes/suggestion-thresholds.md)
  — update that note when changing it.
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
  the originating PR. `all` mode: checks out and scans the `sweep-base`
  input (default `dev` — a scheduled run would otherwise start on `main`),
  one commit on `bot-suggest/<kind>-sweep-YYYY-MM`, force-pushed, + PR
  against `sweep-base`; a re-run in the same month updates that month's
  open PR instead of failing or duplicating it. In both modes only an
  *open* PR counts as existing. `resolve-push-token` provides an App
  token when configured, so the bot's PRs trigger the caller's required
  checks (`GITHUB_TOKEN`-created ones don't) — which is why the
  suggestion jobs skip `bot-suggest/*` head branches, so the bot never
  reviews its own PRs. All `bot-suggest/*` branches are removed by
  `cleanup-suggestion-branch.yml` once their PR is merged or closed.

## STILL OPEN

The user-facing subset of this list is published in `docs/roadmap.qmd`
(no internal details: other accounts, dsSupportClient, App specifics).
Update it when an item here is added, changed or done. Feedback channel:
issues for now (may change — it is named only in `docs/roadmap.qmd#feedback`
and `CONTRIBUTING.md`); no PRs until a branch model and rules exist.

- Versioning: all workflows are referenced `@main`, and `package-release.yml`
  reads its release config from `main` too. The old `v1` tag is unused.
  Decide after the internal feedback round (inputs may still change) and
  once it's clear how to test versioned refs. Proposed shape (not decided):
  - **Branches:** trunk-based — `main` + short-lived feature branches via
    PR, `main` protected (commitlint, `actionlint`). No `dev`: here a
    release is a tag, not a merge into `main`.
  - **Releases:** semantic-release tags `vX.Y.Z` and moves the major tag
    `vX`; callers pin `@v1`; breaking changes (`feat!:`) become `v2`.
  - **Testing:** dsSupportClient points a caller at `@<feature-branch>`.
  - **Prerequisite:** all internal references are hard-coded to `main`
    (`uses: …/actions/…@main`, `.shared-workflows` checkout `ref: main`),
    so a caller on `@v1` or a branch still gets `main`'s actions, scripts
    and prompts. Check out the shared repo at `github.job_workflow_sha`
    and use the composite actions via local path
    (`uses: ./.shared-workflows/.github/actions/…`).
  - **Federation rules** match `job_workflow_ref` exactly (incl.
    `@refs/heads/main`); tags need a prefix/condition match.
- Federation rules for the other two accounts, before rolling out beyond
  dsSupportClient.
- Not yet confirmed in real CI: `all` mode of both suggestion workflows;
  `test-coverage-suggest.yml` actually generating, running and proposing
  tests (it has run on dsSupportClient PR #18, but nothing was needed);
  the version write (`desc_set_version()` in the `prepare` step) — the
  `dev` → `main` chain (head-branch check, `merge-pull-request.yml`,
  release trigger, `package-release.yml`) ran on dsSupportClient PR #20,
  but in `dry-run` mode, which skips `prepare`. dsSupportClient's release
  caller sets `dry-run: true` until its first real release.
- Release config (`.releaserc.json`, `@semantic-release/github`), undecided:
  - `draftRelease`: keep drafts (manual publish after a final look) or
    publish directly?
  - Release comments on issues/PRs: useful as a record that a bug was
    fixed in version X. Currently off. If turned on: plain text such as
    `"Included in version ${nextRelease.version}."` (the default links to
    the release, dead for most readers while it is a draft); only issues
    referenced by commits (`closes #12`) get it; requires **Issues: Read
    and write** on the GitHub App (dsSupportClient's App lacks it) and on
    `docs/getting-started.qmd`, otherwise the first real release fails at
    the comment step, after tag and release exist.
  - `released` label and failure issue: currently off.
- Suggestion thresholds: current accept lists are a first guess. Tune from
  data (log reasons vs. merged/closed suggestion PRs); ideas in
  [dev-notes/suggestion-thresholds.md](dev-notes/suggestion-thresholds.md).
  None of the new behaviour (reasons, deletion notes, reviewing tested
  functions) has run in real CI yet.
- Model per task: all profiles in `config/claude.yml` use the `default`
  model (`claude-sonnet-5`). Tests likely deserve a stronger model than
  roxygen — they matter more, and the add/delete judgment needs better
  reasoning. `config::get()` already merges per profile, so it's a
  `model:` under `test-review` (and possibly `test-failure-classification`).
  Consider enabling thinking there too — it's `disabled` by default
  because it once used up the whole `max_tokens` budget, so it needs a
  larger `max_tokens`. Watch cost per run on the Cost page.
- Shared caching for `R-CMD-Check.yml` — flagged, not started.
- Internal only — keep these off `docs/roadmap.qmd` (user's decision):
  - **Changing existing tests:** the test workflow currently never
    modifies existing tests (it only appends, and reports deletion
    candidates). Revisit whether it may propose changes to them.
  - **Max number of test suggestions:** currently 5 per function and run
    (schema `maxItems`). Revisit the number, and whether a cap per run or
    per sweep is needed.
  - **Author contributions in `DESCRIPTION`:** `check-description-authors`
    adds everyone as `aut` with the full name as given name. Refine how
    contributions are specified (e.g. `aut` vs `ctb`, given/family split)
    — details to be clarified.
  - **README update workflow:** a new workflow that keeps a package's
    README up to date — scope to be clarified.
- Reusable workflow keepalive: GitHub disables scheduled workflows after
  60 days without repository activity. Callers with cron jobs (monthly
  sweeps, scheduled R CMD check, …) currently each add their own
  `liskin/gh-workflow-keepalive@v1` job (dsSupportClient's R-CMD-Check
  caller does, with `actions: write`). Wanted: one centrally maintained
  reusable workflow for it, plus a docs page and example.
