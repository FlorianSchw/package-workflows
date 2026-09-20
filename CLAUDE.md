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

## FILES

- `.github/workflows/check.yml` — reusable R CMD check + codecov. Inputs:
  `os-list`, `r-version-list` (JSON array strings), `run-codecov`, `error-on`,
  `extra-apt-packages`, `extra-r-packages` (plain names, `any::` prefix added
  internally). Done, tested, working.
- `.github/workflows/release.yml` — reusable semantic-release. Checks for a
  caller-repo-root `.releaserc.json` first; falls back to
  `release/.releaserc.json` in this repo via a second checkout into
  `.shared-config`. Done, tested, working end to end (merge → release chain
  confirmed on one real package).
- `.github/workflows/merge-pull-request.yml` — merges the PR via `gh pr merge`.
  No PAT needed (confirmed: doesn't need to re-trigger other workflows, since
  `release` runs via `needs:`, not a fresh `push` event).
- `.github/workflows/create-issue.yml` — posts an issue on check failure,
  using `.github/pr-issue-template.md` from this repo (checked out fresh each
  time). No PAT needed.
- `.github/workflows/R-CMD-Check.yml` — reusable R CMD check matrix
  (last-5-R-versions via `oldrel-1..4`, ubuntu-only default). Done.
- `.github/workflows/roxygen-suggest.yml` — reusable LLM-assisted roxygen2
  doc-suggestion workflow. **Status: `changed`-mode path confirmed working
  end to end, see below.**
- `config/roxygen-style.json` — per-tag writing guidance + `tag_order` array,
  split into `exported`/`internal` profiles (a function's `@export` presence
  decides which profile applies).
- `config/datashield-example-env.json` — canonical demo server + multi-study
  `study_groups` config, used only when a caller sets `datashield: true` and
  `datashield-type: client`. Matched to the calling repo via its `Package:`
  field in `DESCRIPTION`.
- `R/suggest_roxygen.R` — the doc-review script's orchestration entry point
  (env/config wiring + main loop only). Actual logic lives in `R/functions/`
  — one function per file, loaded in bulk via `purrr::walk()`. Claude call
  settings (model, max_tokens, thinking, tool_choice type) live in
  `config.yml` at repo root, not hardcoded. **Status: confirmed working end
  to end on `changed` mode, see below.**

## roxygen-suggest.yml — CURRENT STATUS (most recent work)

**Architecture, settled:** Claude never assembles final roxygen text. It
returns individual prose fields via a forced tool call (`title`,
`description`, `details`, `return_doc`, `examples_body`, `params` keyed by
parameter name) — never `#'` markers or tag labels. The R script
deterministically assembles the final block from those fields, in the exact
order given by `tag_order`. `@export`/`@import`/`@importFrom` lines are
carried forward verbatim from the original file's own roxygen block and
never pass through Claude at all. This design was adopted after two
prompt-only attempts to stop Claude from producing duplicated
old-block-plus-new-block output both failed.

**Auth:** WIF (Workload Identity Federation), not a static API key. Each
caller repo needs its own federation rule (`subject_prefix:
repo:<owner>/<repo>:*`) created in the Claude Console, matched to this
repo's specific `job_workflow_ref` via a `claims` matcher — this closes a
real gap where any workflow in an authorized repo could otherwise mint a
token, not just this one. `ANTHROPIC_ORG_ID` and `ANTHROPIC_SERVICE_ACCOUNT_ID`
are hardcoded as repo-level `env:` (same across every caller); only
`anthropic-federation-rule-id` is a per-caller input (differs per repo).

**Bugs found and fixed today, in order:**
1. Blank line between an existing roxygen block and the function — parser
   didn't tolerate it, misdetected "no existing block," suggestion corrupted
   the function header. Fixed: `parse_r_file()` now skips blank lines before
   checking for `#'` lines, tracks the gap separately, preserves it on
   rewrite.
2. Claude returning a `unexpected end of input` — a deeply nested tool-schema
   literal had a bracket mismatch. Fixed by flattening schema construction
   into named intermediate variables (`build_submit_review_tool()`).
3. Adaptive thinking (default on Sonnet 5) consumed the entire `max_tokens`
   budget before producing any answer. Fixed: `thinking: {type: "disabled"}`,
   `max_tokens: 4096`.
4. Free-text "return only JSON" prompting let Claude preface its answer with
   prose, breaking `fromJSON()`. Fixed: forced tool call instead.
5. Claude concatenating the *entire old roxygen block* followed by a
   *separate new block*, rather than merging — tried twice via prompt
   wording alone (explicit "merge into ONE block" instructions, then also a
   `tag_order` instruction); **both attempts failed**, output identical each
   time. Led to the field-based redesign above.
6. `HTTP 400`: nested tool-schema `params` object's `required` field
   serialized as a malformed JSON *object* (wrong keys) instead of an array.
   Root cause: `vapply()`'s default `USE.NAMES = TRUE` silently attached the
   raw, uncleaned argument text as hidden names on `parsed$params`, invisible
   until `as.list()` preserved them. Fixed: `USE.NAMES = FALSE`.
7. **Most recent, unresolved as of last check:** even after switching to the
   field-based design, one real test run still showed the old-block+new-block
   duplication. Root cause: Claude put the *entire old block, verbatim,
   including its own tag labels* into the `title` field instead of a short
   title — a genuine instruction-following miss, not a script bug (traced
   and confirmed line-by-line against `build_roxygen_block()`). Fix applied:
   `sanitize_field()` strips any line matching `^#'` or `^@[A-Za-z]+` from
   every Claude-supplied field before assembly, and hard-fails loudly
   (`stop()`) if a required field is empty after stripping — so this failure
   mode can no longer silently reach a real PR suggestion.

**CONFIRMED:** fix #7 (`sanitize_field()`) works. Verified via a genuinely
fresh run on `dsSupportClient` PR #4 (triggered by a trivial commit, checked
via the GitHub API's `original_commit_id` on the posted review comment to
rule out reading a stale/historical comment) — single, non-duplicated block,
no leaked roxygen syntax in any field.

**Two follow-up fixes, also confirmed on fresh runs after #7:**
8. `title`/`description` were assembled as bare untagged paragraphs (the
   idiomatic roxygen2 style), but the desired convention for this project is
   explicit tags. Fixed: `build_roxygen_block()` now emits
   `#' @title ...` / `#' @description ...`, matching the `@details`/`@param`/
   `@return` pattern already used elsewhere.
9. Leftover blank `"#'"` separator lines after `title`/`description`/
   `details` — a holdover from when those were bare paragraphs and roxygen2
   needed a blank comment line to delimit them. No longer needed now that
   every section has its own explicit tag, and inconsistent with
   `param`/`return`/`import`/`examples`/`export` (which never had them).
   Fixed: removed; all sections now assemble back-to-back with no gaps.

`roxygen-suggest.yml` / `suggest_roxygen.R` can be considered done for the
core `changed`-mode path. Remaining open items are listed below.

## Still open / not yet done
- Not yet tagged `v1` — everything still referenced via `@main` by callers.
  Deliberate for now, while iterating; revisit once things stabilize.
- Two more federation rules needed (personal account, second org) once
  ready to roll this out beyond `dsSupportClient`.
- Monthly-sweep mode (`scan-mode: all`) — built, never actually tested yet.
- Shared caching for `check.yml` — flagged, not started.
- `R/suggest_roxygen.R` was split into one function per file under
  `R/functions/` (loaded via `purrr::walk()`), plus `config.yml` for Claude
  call settings, at the user's explicit request. Done.
