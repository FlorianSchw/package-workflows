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
  head may be a fork); it comments a preview instead (see below).
- **Diagrams:**
  - **Overview:** one lane per main event (PR into `dev`, PR into `main`,
    PR closed, push, …), each workflow once, as a box with its `name:` and
    the file name in small print. Further triggers and path filters as
    small print in the box ("R/** only · also: monthly · manual").
    Arrows between workflows only for chains (`workflow_run`,
    `repository_dispatch`, `gh workflow run`). No jobs. A first draft with
    one arrow per trigger→workflow was an unreadable tangle — grouping by
    event is the fix.
  - **Detail, one per workflow:** jobs as boxes, `needs:` as arrows
    labelled with their condition (success / failure), called reusable
    workflows in small print as the **full reference**
    `owner/repo › file@ref` (the same repo name can exist in several
    accounts), job-level `if:` conditions as notes.
- **Called workflows are read** at the referenced ref via the GitHub API —
  needed to find chains that start inside them (e.g.
  `trigger-release-publish.yml` sends `repository_dispatch`, which starts
  the caller's `release-publish.yml`). Reading is for chain detection
  only: diagrams still show each called workflow as one box.
  - **Depth:** workflow calls are followed all the way down (loop guard,
    depth cap). A "level" is a workflow calling a reusable workflow;
    composite actions used in a job's steps are not a level and are **not
    opened** — a dispatch sent from inside an action is missed
    (documented gap). In package-workflows nothing nests today (no
    reusable workflow calls another; the only dispatch is a plain `run:`
    step in `trigger-release-publish.yml`), so one level would suffice
    there; deeper is for other repos.
  - **Access:** public repos work with the default token; private ones in
    other accounts need a token with read access. An unreadable file
    still gets its box, with a "(not readable)" note.
- **Chain detection is partly heuristic:** `workflow_run` is explicit (the
  listener names the workflow). Dispatches are sent from steps, so only
  known forms are recognised (`gh api …/dispatches`, `gh workflow run`,
  common dispatch actions); an unrecognised form gives no arrow, never a
  wrong one.
- **Marked blocks:** the generator only replaces content between its
  markers, found by ID, not position:
  `<!-- workflow-graphs:overview:start -->` … `:end -->` and
  `<!-- workflow-graphs:detail:<file>:start -->` … `:end -->`.
  - No README yet: created with a short starter text (written only this
    once), the overview block, and a heading + block per workflow.
  - Later runs: only block contents change; text around the blocks and
    block order stay as the user left them. Each detail block contains
    its own `###` heading (workflow name, file in small print), so a
    renamed workflow's heading follows; the `##` section headings of the
    starter text are the user's.
  - New workflow file: block (with heading) appended at the end.
  - Deleted workflow: its block is removed; surrounding text stays.
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
- **On `pull_request`:** no commit; a comment with a preview of the
  diagrams as they'll look after the merge (GitHub renders Mermaid in
  comments), noting that nothing is committed on PRs — also makes a caller
  wired to `pull_request` only obvious. Updated in place on further pushes.
  Caller needs `pull-requests: write`.

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
