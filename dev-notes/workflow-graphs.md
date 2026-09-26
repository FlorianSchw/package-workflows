# workflow-graphs.yml

Reusable workflow that draws Mermaid diagrams of a repository's GitHub
Actions workflows into `.github/workflow-graphs/README.md`. Status: built,
tested locally on 2026-09-26; first CI run on dsSupportClient generated the
README but the push failed (see "Where"); location changed, rerun pending.
Open points at the end.

## Decisions

- **Where:** `.github/workflow-graphs/README.md`. GitHub renders a folder's
  `README.md` when browsing it, so people looking at the automation find
  it; package users reading the root README don't. Never
  `.github/README.md` — GitHub gives that one priority over the root
  README, so it would replace the repo's front page.
  ~~`.github/workflows/README.md`~~ (first choice): GitHub treats **every
  file** in `.github/workflows/` as a workflow, and a GitHub App may only
  create or change those with the **Workflows** permission — the first CI
  run on dsSupportClient was rejected with GH013 "refusing to allow a
  GitHub App to create or update workflow … without `workflows`
  permission". Granting it would let App tokens change real workflows in
  every installed repo (scoping tokens per workflow was the mitigation
  considered). User chose a folder of its own instead (2026-09-26): one
  extra click (`.github/` → `workflow-graphs/`), no new permission, and
  the README is outside the trigger paths, so no path exclusion needed.
  `GITHUB_TOKEN` can never change workflow files, so it's no fallback for
  the old location either.
- **Deterministic:** diagrams come from parsing the YAML only, no Claude.
  Exact, free, same output for the same input.
- **Language: R** (user's choice, 2026-09-26), for one language across the
  repo — entry script `R/workflow_graphs.R`, logic in `R/functions/workflow-graphs/`, one
  function per file, `yaml` package. The ~30–60 s R setup per run was
  accepted: callers are R repos, and a non-R repo can still use it.
  Revisable later (Python was the alternative).
- **Mermaid** (rendered natively by GitHub in Markdown): plain text in the
  README, readable diffs, no image files or graphics tools.
- **No suggestion PR:** the diagrams are facts, not suggestions, so the
  workflow commits directly (`docs: update workflow diagrams` — `docs:`
  never triggers a semantic-release version bump).
- **Trigger (in the caller):** `push` to the branch where merges land —
  `dev` in the two-branch model, `main` in repos without `dev` — with
  `paths: ['.github/workflows/**']`, plus
  `workflow_dispatch`. No `branch` input: the workflow commits to the
  branch it was started on (`github.ref_name`); a manual run uses the
  branch picked in the Actions UI. On `pull_request` it never commits (the
  head may be a fork); it only leaves a short note (see below).
- **Content: high level only** (user's decision, 2026-09-26, third
  round): a summary table and one diagram per situation. Specifics are in
  the workflow files. History: v1 one wide overview with a lane per main
  event (unreadable, GitHub clipped labels, `<small>` had no effect);
  v2 added per-workflow detail diagrams opening up the called workflows'
  jobs and steps — dropped in v3 as too specific, and the table already
  says what a workflow calls.
  - **Summary table** (`workflow_summary_table()`, rows in
    `workflow_order()`: situation by situation, chain targets right after
    their source): *Name*, *File* (the only place the file is named),
    *Runs on* (triggers with all path filters — no "+3"), *Calls* (full
    reference `owner/repo › file@ref`), *Produces* (outcome — *condition*,
    plus "starts **X**"). A cell with several entries uses "• " bullets.
  - **What runs when** — heading plus one sentence, then per situation
    (`workflow_situations()`) a `####` heading in words
    (`situation_title()`: "When a pull request into dev is opened or
    updated") and a diagram (`situation_diagram()`): event (short label)
    → workflows (box: name, path filter or schedule, and a condition
    shared by all its outcomes) → chain targets (dotted, followed down) →
    outcome boxes (dashed, shared per wording). Manual runs and
    `workflow_call` get no diagram; a dispatch/`workflow_run` situation is
    dropped when its workflows are already chain targets.
  - **Conditions fitted per situation** (`situation_outcomes()`): an
    outcome "only on <other event>" is left out ("Scheduled workflows kept
    enabled" not in the PR diagram), on its own event the condition is
    dropped; a condition shared by all remaining outcomes of a workflow
    goes once into its box, only differing ones on the arrows ("if check
    succeeds" / "if check fails"). This removed the overlapping labels of
    v2 (several identical "skipped for PRs from bot-suggest/ branches"
    labels on converging arrows); checked by measuring label/box
    rectangles in the rendered SVG — no overlaps left.
  - **Spacing:** `%%{init: {"flowchart": {"rankSpacing": 140,
    "nodeSpacing": 45}}}%%` so labels fit between the columns; condition
    labels wrapped at 20 characters.
  - **Labels** are wrapped in R (`mermaid_label()`, 26 characters, long
    names broken after "/" then "-"), since GitHub's Mermaid clips instead
    of growing a box. `*` is escaped (Mermaid and Markdown read `R/**` as
    bold). Mermaid reserves `call` (click callbacks) — a class named
    `call` breaks the whole diagram.
  - Conditions in words where common (`describe_condition()`: "only on
    schedule", "skipped for PRs from bot-suggest/ branches", "only if the
    PR comes from dev"), else the full expression — never truncated.
- **Outcomes** come from `config/workflow-outcomes.yml` (user's choice,
  2026-09-26): short names with wording, and per workflow — reusable as
  `owner/repo/path` without ref, the repo's own as
  `.github/workflows/<file>` — what it produces: a short name, own wording
  with `{input}` placeholders (filled from the calling job's `with:`,
  else the input default: "Check: PR comes from {allowed-head}" → "…
  dev"), or `{outcome, only-on: <event>}` for results that depend on the
  event (workflow-graphs commits only on push, comments only on PRs;
  suggestion workflows comment only on PRs, not in sweeps). Outcomes are
  per job and carry the job's run condition (`job_run_condition()`: the
  caller job's `if:`, "if check fails" for needs-results, plus a condition
  shared by all jobs of the called workflow). Overridable per repo via
  `resolve_shared_path()`. Not derivable from the YAML.
- **Fourth round** (2026-09-26, after the live README):
  - Sections "## All workflows" and "## Events" (not "situations") come
    with the block; each diagram titled with the short form ("### PR into
    dev") and the sentence in italics below. `drop_old_starter_headings()`
    removes the "## Overview" (directly before the block) and the empty
    "## Workflows" of the earlier starter — only in exactly that shape.
  - Boxes: bold workflow name; notes as **only if:** / **skipped:**
    (`describe_condition()`, `event_filter()`, `event_noun()`), explained
    in the legend under "Events" and used in the table too.
  - **Outcomes follow the job order** (`situation_diagram()`, user-found
    bug): Release used to draw four arrows from its box. Now an outcome
    starts from the outcomes of the jobs its job `needs` (label: the
    awaited result), a job without outcomes passes arrows through, and a
    chain starts from the outcome its sending job depends on — so check →
    PR merged (if check succeeds) / Issue (if check fails), PR merged ⇢
    Publish Release. Outcomes that lead on get a box per workflow, leaf
    outcomes stay shared by wording. `workflow_outcomes()` now records the
    job and keeps the needs-result (`needs`) apart from other conditions.
  - Deep diagrams top to bottom: GitHub scales a diagram to the page
    width, and "PR into main" (event → Release → check → merged → Publish
    Release → release, six columns) came out tiny left to right. A
    diagram more than four columns deep (longest path from the event) is
    now drawn `TD` with `rankSpacing` 70; measured locally: rendered at
    full size (595 px) instead of shrunk.
  - Not derivable: that Require Head Branch blocks the merge — that's a
    branch ruleset, not in the YAML (and not readable with the job's
    token). Stated on the docs page as a general limit.
- **Keepalive jobs** stay (user's choice, 2026-09-26) — as an outcome in
  the table and the schedule diagram.
- **Called workflows are read** at the referenced ref via the GitHub API —
  needed to find chains that start inside them (e.g.
  `trigger-release-publish.yml` sends `repository_dispatch`, which starts
  the caller's `release-publish.yml`) and conditions shared by their jobs.
  - **Depth:** workflow calls are followed all the way down (loop guard,
    depth cap). A "level" is a workflow calling a reusable workflow;
    composite actions used in a job's steps are not a level and are **not
    opened** — a dispatch sent from inside an action is missed
    (documented gap). In package-workflows nothing nests today.
  - **Access:** public repos work with the default token; private ones in
    other accounts need a token with read access. An unreadable call is
    marked "not readable" in the table, and the run logs a warning
    (also for a temporary API problem — seen locally when the
    unauthenticated rate limit ran out).
- **Chain detection is partly heuristic:** `workflow_run` is explicit (the
  listener names the workflow). Dispatches are sent from steps, so only
  known forms are recognised (`gh api …/dispatches`, `gh workflow run`,
  common dispatch actions); an unrecognised form gives no arrow, never a
  wrong one.
- **Marked block:** the generator only replaces the content between
  `<!-- workflow-graphs:overview:start -->` and `…:end -->`, found by ID.
  No README yet: created with a short starter text (written only once)
  and the block. Blocks no longer generated are removed (the
  `detail:<file>` blocks of v2 disappear on the next run; the user's
  `## Workflows` heading from the v2 starter stays until deleted by hand).
  ~~Detail blocks follow `workflow_order()`, text below one moves with
  it~~ (v2, obsolete with the detail blocks).
- **Name:** `workflow-graphs.yml` (decided 2026-09-26; not a suggestion,
  so not `*-suggest`).
- **Commit step:** a new shared composite action
  `.github/actions/commit-and-push` (name not final): commits the listed
  files to the **current** branch in one commit, pushes (pull/rebase retry only if the branch moved on — any other rejection fails at once,
  extraheader reset as in `commit-updated-files.sh`), does nothing if
  nothing changed. Inputs: file list, commit message, token. A shared
  action rather than an inline step because a second user is expected: a
  future Pages workflow that generates `docs/`/`examples/`, commits them,
  then publishes (user's idea, 2026-09-26, not designed). Nothing uses a
  plain commit today (`commit-updated-files` → `bot-suggest/` branch + PR;
  semantic-release commits itself; `publish-docs.yml` doesn't commit).
  `commit-updated-files` stays as is: its commit/push/PR steps are
  specific to suggestion PRs (new branch, per-file commits, force-push);
  splitting it would only share the push line and add more `@main`
  references (see the versioning item in CLAUDE.md).
- **On `pull_request`:** no commit, and ~~a comment previewing the
  diagrams after the merge~~ (dropped 2026-09-26, user's choice) only
  one short comment (`comment_once()`, so not repeated on further pushes):
  a commit can't be placed on a pull request, run it on push or by hand
  instead, with a link to the example caller. The script stops right
  there, before reading any workflow. The example caller has no
  `pull_request` trigger, so the comment only appears when a caller is
  wired up that way. Caller needs `pull-requests: write` for it.

## Caller consequences

- If the target branch requires PRs, the pushing identity needs a bypass —
  the GitHub App (already a bypass actor on `main` for the release), via
  `resolve-push-token`.
- `concurrency` group per branch, and pull/rebase before pushing, so two
  quick merges don't make the second run fail.
- The README is outside the trigger paths, and a rerun gives identical
  output (nothing to commit) — no loop.

## Open points

- Layout details, decided on a first real draft: small-print format, how
  to show schedules (cron as text vs. "weekly"/"monthly"), long
  conditions.
- Docs page + example caller once built.
