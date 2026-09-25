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
    their GitHub profile name and credits them in `DESCRIPTION` via a
    `bot-suggest/authors` sub-PR: `aut` if any of their commits changed
    `R/*.R`, else `ctb`; an existing `ctb` is upgraded to `aut`, nobody is
    downgraded or removed, other roles stay. Merge commits don't count.
    Reasons go into the sub-PR body (`suggestion_report.md`). Needs a
    caller trigger on all PRs (no `paths` filter), or tests/docs-only
    contributors are never seen. Bots are skipped per
    `config/bot-authors.json` (overridable, see `resolve_shared_path()`
    below). New people: name split by `split_person_name()` (last word +
    particles like `van`/`de` = family; one-word names flagged). Matching
    (`find_author()`): commit e-mail (noreply ignored; e-mails are never
    written) or name ignoring case/accents/punctuation/order; same family +
    initial is only reported as "may already be listed" — in the sub-PR
    body, or via `comment_once()` on the PR if nothing else changed.
    `desc` writes `Authors@R` in its standard (tidyverse) format — a
    hand-formatted field is normalized once; deliberately not customized.
  - `roxygen-suggest.yml`, `test-coverage-suggest.yml` — LLM-assisted
    suggestion workflows; see below.
  - `cleanup-suggestion-branch.yml` — on PR close, deletes a `bot-suggest/*`
    head branch unless another open PR still uses it.
  - `workflow-keepalive.yml` — wraps `liskin/gh-workflow-keepalive@v1`
    (user's choice over custom `gh api` code). Inside a reusable workflow
    `GITHUB_WORKFLOW_REF` is the caller's, so it re-enables the calling
    workflow, resetting GitHub's 60-day inactivity timer. Callers add it
    as a job (`if: github.event_name == 'schedule'`) to each scheduled
    workflow.
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
  from `examples/` — generic caller files, `@main`. The tables follow
  workflow changes automatically; page prose, examples and
  `docs/roadmap.qmd` are updated in a batched docs pass when the user asks
  — until then, note what's needed under "Docs pending" in STILL OPEN.
  Preview with `quarto preview docs`.

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
  **Pitfall:** `actions/checkout` stores `GITHUB_TOKEN` as an extra HTTP
  header (`persist-credentials`) that wins over a token in the remote URL.
  Pushes must reset it (`git -c "http.https://github.com/.extraheader="
  push`, `git_push_with_token()` in `commit-updated-files.sh`), otherwise they go
  out as `github-actions` and the PR's workflows need approval / don't
  run (seen on the force push to dsSupportClient PR #25).

## STILL OPEN

The user-facing subset of this list is published in `docs/roadmap.qmd`
(no internal details: other accounts, dsSupportClient, App specifics).
Update it when an item here is added, changed or done. Feedback channel:
issues for now (may change — it is named only in `docs/roadmap.qmd#feedback`
and `CONTRIBUTING.md`); no PRs until a branch model and rules exist.

- Docs pending (for the next batched docs pass):
  - `check-description-authors.qmd`: the `aut`/`ctb` rule, upgrades, merge
    commits skipped, reasons in the suggestion PR; replace the "full name
    as given name" callout with: name split (and its limits, e.g. two-part
    Spanish surnames), how existing entries are recognised, "may already
    be listed" notes, and the one-time normalization to the tidyverse
    `Authors@R` format.
  - `examples/check-description-authors.yml`: drop the `paths` filter
    (all PRs into `dev`), and say why on the page.
  - `suggestions.qmd`: the example comment/title for authors is now
    "Update contributors in DESCRIPTION"; tests now "Test suggestions".
  - `test-coverage-suggest.qmd`: existing tests are reviewed (update /
    delete / report, safeguards, history evidence), max 10 new tests,
    quality rules, stronger model; "Tests that could be deleted" section
    and "Existing tests are never changed" bullet are outdated; sweep
    scope inputs (`sweep-lookback-days`, `sweep-rotation-months`).
  - `suggestions.qmd` "What gets proposed": add the existing-test actions.
  - `roadmap.qmd`: "Model per task" is done for tests.
  - `test-coverage-suggest.qmd`: packages without testthat get it set up
    (`tests/testthat.R`, `Suggests`, edition 3 only when fresh) — also a
    note in Getting started that the test workflow needs no prior setup;
    the link comment and PR description start with a one-line statistic.
  - `suggestions.qmd`: example link comment now includes the statistic line.
  - `roxygen-suggest.qmd`: the PR description groups "Applied changes (n)"
    per file and "No changes applied (n)" per reason, with Claude's
    proposed text; untagged titles/descriptions are kept; possible code
    bugs are reported in the suggestion PR (fallback: comment on the PR);
    the link comment shows a statistic line.
  - `test-coverage-suggest.qmd` DataSHIELD section: an existing DSLite
    setup is found in any `setup*.R` / `helper*.R` and shown to Claude
    (own names and helpers are used); a generated setup goes to
    `setup.R`, or `setup-dslite.R` if a `setup.R` without DSLite exists
    (revisable after feedback). Claude also gets the structure of
    the test data (rows, columns, types, missing values, factor level
    counts — the level counts are the only data values shared; mention it).

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
  ~~`test-coverage-suggest.yml` actually generating, running and proposing
  tests~~ confirmed on dsSupportClient PR #21 → sub-PR #24 (tests for an
  already-tested function, `bad_test` classification comment, sub-PR
  updated instead of duplicated); deletion notes not yet seen;
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
  Ran in real CI on dsSupportClient PR #21 (reviewing tested functions
  confirmed); whether reasons dropped anything is only in the job logs,
  and no deletion notes were produced yet.
- ~~Model per task: all profiles in `config/claude.yml` use the `default`
  model (`claude-sonnet-5`). Tests likely deserve a stronger model than
  roxygen~~ Done: `test-review` and `test-failure-classification` use
  `claude-opus-5` with adaptive thinking, `effort: high`, larger
  `max_tokens` (32000 / 16000) and the server-side refusal fallback
  (`fallbacks: default` + beta header); `call_claude_tool()` stops with a
  clear error on `max_tokens` / `refusal`. Roxygen stays on Sonnet 5.
  Still open: watch cost per run on the Cost page (tests now review every
  selected function with Opus). Forced tool calls with thinking work on the
  Claude API; they would 400 on Opus 5.5 / Fable 5.1 (use `auto` then).
- Shared caching for `R-CMD-Check.yml` — flagged, not started.
- **Rename the workflows before rolling out to more repos:** names are
  mixed and partly outdated (`test-coverage-suggest` now also updates and
  deletes tests). Proposal (not decided): prefixes by group — `check-*`
  (`check-r-package`, `check-commit-messages`, `check-pr-source-branch`),
  `release-*` (`release-package`, `release-trigger`, `release-merge-pr`,
  `release-failure-issue`), `suggest-*` (`suggest-roxygen-docs`,
  `suggest-tests`, `suggest-authors`, `suggest-cleanup-branches`),
  `maintain-keepalive`. Breaking: every caller's `uses:` path and the
  federation rules' `job_workflow_ref` claims change; docs/examples too.
  Combine with removing `app-id` (both need caller changes).
- **Policy file for the bot's rules** (`config/suggestion-policy.yml`):
  today reasons, action↔reason mapping, the `aut`/`ctb` rule, name
  particles and report routing live partly only in R code. Move the
  tunable policy to one readable file that R and the tool schemas read
  (schema descriptions from the same source); keep safety invariants
  (never adapt a test to possibly buggy output, only failing tests are
  updated, nothing without a suggestion PR) in code, documented in the
  decision record. Overridable per repo like the other config files.
- **Report routing is code, not config:** where test failures, possible
  bugs, deletion notes and code issues go (PR comment, PR description,
  issue, log) is decided in R (`publish_test_report()`,
  `suggest_roxygen.R`). The user expects it to be configurable — do it as
  part of the policy file (`config/suggestion-policy.yml`, see "rules
  partly only in code"). Constraint: an issue needs `issues: write`,
  which roxygen callers don't grant.
- **GitHub App `client-id` (soon, user wants it possibly today):**
  `actions/create-github-app-token@v3` deprecates `app-id` in favour of
  `client-id` — a *different value* (the App's Client ID, `Iv23li…`, not
  the numeric App ID). Plan: `resolve-push-token` and the workflows accept
  an additional `app-client-id` secret and prefer it; `app-id` keeps
  working (with the warning) during transition; callers add a secret
  `APP_CLIENT_ID`. Remove `app-id` later, together with the workflow
  renaming (both need caller changes).
- **Ubuntu 26 on `ubuntu-latest` from 2026-10-19:** P3M binaries
  (`use-public-rspm`) may lag for a new Ubuntu → source builds, slow or
  failing. Plan: pin all workflows (and R-CMD-Check's `os-list` default)
  to `ubuntu-24.04` before then; move to 26.04 deliberately once P3M
  serves binaries for it, tested on dsSupportClient first.
- Internal only — keep these off `docs/roadmap.qmd` (user's decision):
  - **Name of a generated DSLite setup file:** `setup.R` if none exists,
    else `setup-dslite.R` (must start with `setup` for testthat to run
    it). Chosen to avoid cluttering packages with files; revisit after
    colleagues' feedback.
  - ~~**Changing existing tests:** the test workflow currently never
    modifies existing tests~~ Done: existing tests are updated / deleted /
    reported under the safeguards in `dev-notes/suggestion-thresholds.md`,
    using test results and history evidence (function diff in PRs).
    Tested locally end to end (mocked Claude), not yet in CI — replay a
    PR like #21 (contract change + outdated test) as the first real check.
  - ~~**Max number of test suggestions:** currently 5~~ Done:
    `max_new_tests` (10) in `config/claude.yml`. Sweep cost is handled by
    scope instead: `sweep-lookback-days` / `sweep-rotation-months` in
    `test-coverage-suggest.yml` (recently changed + rotating share; tested
    locally). A cheaper sweep model was considered and not done — the
    existing-test diagnosis needs the strong model.
  - **Author contributions in `DESCRIPTION`:** ~~`aut` vs `ctb`~~ done
    (`R/` changes → `aut`, otherwise `ctb`, upgrade only; tested locally
    with a mocked GitHub API, not yet in CI). ~~**Names** — the full name
    is added as given name, and `find_author()` matches by plain text~~
    done (given/family split, e-mail/normalized-name matching, possible
    matches reported; replayed PR #21 locally). Decided against for now:
    a per-repo login → name mapping file (`config/authors.json`) —
    revisit only if wrongly split or differing profile names become a
    real problem. Later option: a minimum change size for `aut`, and
    `Co-authored-by:` trailers.
  - **README update workflow:** a new workflow that keeps a package's
    README up to date — scope to be clarified.
- ~~Reusable workflow keepalive: GitHub disables scheduled workflows after
  60 days without repository activity. Callers with cron jobs (monthly
  sweeps, scheduled R CMD check, …) currently each add their own
  `liskin/gh-workflow-keepalive@v1` job (dsSupportClient's R-CMD-Check
  caller does, with `actions: write`). Wanted: one centrally maintained
  reusable workflow for it, plus a docs page and example.~~ Done:
  `workflow-keepalive.yml`. Not yet run in real CI; dsSupportClient's
  R-CMD-Check caller still uses `liskin` directly, and its suggestion
  callers have no keepalive yet.
