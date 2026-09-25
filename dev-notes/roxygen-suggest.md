# roxygen-suggest.yml

Reusable workflow that reviews each function's roxygen2 documentation for
completeness and accuracy with Claude, rewrites the block, and proposes the
result as a suggestion PR. Shares auth, config and R conventions with
[test-coverage-suggest.yml](test-coverage-suggest.md) (see `CLAUDE.md`).

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
   (n)" per reason. Claude also returns `code_issues` (likely defects in
   the code, not the docs): a comment on the originating PR in a PR run
   (`comment_once()`), a "Possible bugs in the code" section of the sweep
   PR in a sweep, only the log if a sweep opens no PR.
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
