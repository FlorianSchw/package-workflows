# roxygen-suggest.yml

Reusable workflow that reviews each function's roxygen2 documentation for
completeness and accuracy with Claude, rewrites the block, and proposes the
result as a suggestion PR. Shares auth, config and R conventions with
[test-suggest.yml](test-suggest.md) (see `CLAUDE.md`).

## How it works

Entry script: `R/suggest_roxygen.R`. Per file in `files_to_check.txt`:

1. `parse_r_file()` finds the (first) function, its params and the roxygen
   block above it, grouping every tag with its continuation lines.
2. `select_profile()` picks the `exported` or `internal` guidance from
   `config/roxygen-style.json` (by `@export` presence).
3. `ask_claude_for_review()` (profile `roxygen-review`, prompt
   `prompts/roxygen-review-prompt.md`) returns prose **fields** — title,
   description, details, return, examples, one entry per param — via a
   forced tool call, plus `changes`: each changed field with a reason.
   Never `#'` markers or tag labels.
4. `accepted_roxygen_fields()` applies the threshold (accepted reasons,
   more than a whitespace/punctuation/case difference — see
   [suggestion-thresholds.md](suggestion-thresholds.md)); nothing accepted
   → the file is skipped. Applied and dropped changes (with reason,
   explanation and proposed text) go to `format_roxygen_report()` →
   `suggestion_report.md` → the suggestion PR's description, as
   collapsible groups: "Applied changes (n)" per file, "No changes applied
   (n)" per reason; heading levels and spacing are set in
   `config/report-style.yml` (GitHub strips CSS). Claude also returns `code_issues` (likely defects in
   the code, not the docs), shown as "Possible bugs in the code" in the
   same description. On top, a one-line statistic
   (`format_roxygen_summary()`), repeated in the link comment on the
   originating PR. Without a suggestion PR, bugs go to a comment on the
   originating PR (`comment_once()`). In a sweep they go to that month's
   issue "Roxygen sweep: possible bugs in the code (YYYY-MM)"
   (`report_sweep_code_issues()`); a rerun comments on the open one
   instead of opening another. This needs `issues: write`, which callers
   grant since 2026-09-30 (user's decision); before, it was log only.
5. `build_roxygen_block()` assembles the block deterministically in
   `tag_order`, taking Claude's text only for accepted fields and the
   original lines for all others; `write_in_place()` swaps it into the file.
6. Rewritten files are listed in `updated_files.txt`; the
   `commit-updated-files` action commits them — in `changed` mode onto
   `bot-suggest/docs/<PR branch>`, opened as a sub-PR into the PR branch
   (with a link comment on the originating PR), in `all` mode as a sweep
   PR against `dev`.

For DataSHIELD packages, `role_guidance()` adds client/server guidance from
`config/datashield-role-guidance.json`. For client packages matching a
`study_group` in `config/datashield-example-env.json` (by `Package:` in
`DESCRIPTION`), the prompt also carries a canonical multi-study Opal login
example to use in `@examples`.

**Utility packages** (`datashield-type: utility`, 2026-09-29) are
analyst-side helpers such as dsAnalysis or mepr: project setup, mock data,
packages. They get their own guidance, which covers side effects, and
examples that write to `tempdir()`. The login example is included only for
files whose function uses DataSHIELD connections, judged by
`uses_ds_connections()`: a `datasources` argument, `datashield.*()` or
`ds.*()` calls. Their study group is found through the package itself or
its `Depends`/`Imports` (`read_package_dependencies()`, e.g.
`dsBaseClient`), so the example environment needn't list every utility
package. An unknown `datashield-type` stops the run
(`check_datashield_type()`); it used to be skipped silently.

## Design decisions

- **Claude never writes final roxygen text** — only fields, which R stitches
  together. Adopted after two prompt-only attempts to stop Claude emitting
  the old block followed by a new one both failed identically.
- **Only six tags are Claude-managed**: title, description, details, param,
  return, examples. Every other tag in the existing block (`@export`,
  `@import`, `@author`, `@seealso`, `@section`, ...) is carried forward
  verbatim, including multi-line ones. Nothing needs registering; unknown
  tags go where `"*"` sits in `tag_order`.
- **Explicit `@title` / `@description` tags**, no blank `#'` separator lines
  between sections (project convention).
- **Defense in depth on Claude's fields:** `strip_artifact_lines()` removes
  leaked `#'`/`@tag` lines; an empty required field after stripping is a
  hard error, never a silently broken block.

## One report per bot PR, possible bugs with a verdict (built 2026-10-02)

**Why:** on dsSurvivalClient PR #37, a one-line push re-ran the review of
`R/ds.acmPlot.R`. Claude saw the branch's own docs (the first suggestion
lived only on the bot branch), so it suggested nearly the same five fixes
again in other words, and the description grew a second complete report
("Update for ed1fbb9"). A possible bug ("x_breaks leaks across
studies") was wrong in run 1; in run 2 the summary repeated it and the
explanation, written after it, refuted it.

**What it does now** (PR and push runs that build on an open bot PR,
`open-suggestion-pr: add`, no rebuild):
- **State:** all findings live hidden in the bot PR's description,
  `<!-- bot-suggest-state: <base64 JSON> -->` (user's choice over a
  file on the bot branch, which would be merged into their branch).
  `decode_suggestion_state()` / `encode_suggestion_state()`; over 25000
  characters, crossed-out entries are dropped from the state first.
- **Review on top of the proposal:** `review_source_block()` gives Claude
  the block the bot branch proposes, assembled in a temporary copy, so
  `write_in_place()` writes the user's file with the bot's block plus
  this run's changes. Exception: the user's block differs from the one
  at `BASE_REV` (they edited the docs) — then theirs is reviewed, as in
  the bot branch's merge (`-X theirs`), and the bot's earlier applied
  entries for the file are crossed out.
- **Earlier findings to Claude:** open not-applied suggestions and bugs of
  the file, with ids (`format_earlier_findings()`). Schema:
  `repeats_earlier` (enum of ids) on changes and code issues,
  `earlier_findings` (still_valid / superseded / resolved + note).
- **Merge** (`merge_roxygen_findings()`), never deleting: user edit →
  earlier applied crossed out; Claude's judgement → crossed out; a new
  applied change → earlier entries on the same field crossed out; a
  repeat → skipped; a new not-applied suggestion → older ones on the
  same field crossed out.
- **Report** (`format_roxygen_report()`), rebuilt from all entries each
  run: counts = open entries, each tagged with its commit, crossed-out
  ones struck through with when and why; a "Latest review" line; a
  pre-format description (e.g. #37's) kept in a collapsed "Earlier
  reports" section, carried forward. `commit-updated-files` gets
  `pr-body-mode: replace` (roxygen); the test workflow keeps `append`.
- **Possible bugs:** schema order explanation → verdict (`defect` /
  `not_a_defect` / `unsure`) → confidence (`high` / `medium` / `low`) →
  summary; `kept_code_issues()` keeps `defect` with a confidence from
  the `code-issue-confidence` input (e.g. `"high"`, user's request: per
  repository without copying `config/claude.yml`), else
  `code_issue_confidence` in `config/claude.yml` (default high + medium,
  user's choice); an unknown level stops the run
  (`code_issue_confidence_levels()`). Medium is labelled in the report.
- **Test report stays `append`** until it gets the same merge scheme:
  its report covers only the current run, so replacing would lose the
  earlier runs' findings. `max_tokens` for
  roxygen raised to 8192 for the reasoning.
- **Fresh start:** no open bot PR, `open-suggestion-pr: replace`, a
  rebuild, and sweeps (rebuilt monthly branch) start without state.

**Known edges:**
- **Merge fallback:** if the commit action can't merge the branch into
  the bot branch, it rebuilds it with this run's files only, but the
  report still lists earlier applied changes as open; the action's note
  says so.
- **Hand edits to the bot PR's description** are overwritten on the next
  run.

**Later, if wrong bugs still slip through:** adaptive thinking for the
roxygen review (like the test review). Costs more on every run; note the
pitfall below — set `max_tokens` well above the thinking budget.
Deliberately not done yet (user's decision, 2026-10-02), and neither is
skipping whitespace/comment-only changes — the user triggers runs with
such commits to observe behaviour.

**Tested locally** (real entry script; Claude and the PR lookup mocked; a
real bot branch in a bare remote): two runs modelled on #37 — run 2
reviewed the bot's block, kept run 1's description, added one change,
skipped two repeats, crossed out the wrong bug with its reason; a user
edit of the docs (their block reviewed, earlier applied entry crossed
out); a pre-format description kept and carried forward; the state
round trip with umlauts and `-->`; `commit-updated-files.sh` in both
body modes with a `gh` stand-in. **Not yet in CI.**

## Pitfalls already hit (don't regress)

- A blank line between block and function must not read as "no block" —
  the gap is tracked and preserved.
- Adaptive thinking (default on Sonnet 5) used the whole `max_tokens`
  budget before answering → `thinking: disabled` in `config/claude.yml`.
- Free-text "return only JSON" got prose prepended → forced tool call.
- `vapply()`'s default `USE.NAMES = TRUE` attached raw argument text as
  names on `params`, which serialized the schema's `required` as a JSON
  object (HTTP 400) → `USE.NAMES = FALSE`.
- Claude once put the entire old block into `title` → artifact stripping.

## Status

`changed` mode confirmed end to end on dsSupportClient PR #18: caller-secret
WIF auth, sub-PR #19 into the PR branch (opened although merged PR #12
used the same sub-branch name — the existence check only counts open PRs),
and the link comment on #18, posted with the App token; the sub-branch was
deleted by `cleanup-suggestion-branch.yml` once #19 was merged. `all` mode
(monthly sweep) has not run in CI yet; its commit/PR logic was verified
locally.
