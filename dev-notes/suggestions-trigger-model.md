# Trigger model for the suggestion workflows (design, not built)

Status: **built on 2026-10-01 and tested locally** (sandbox repos with
`gh`/`jq` stand-ins, see "Implementation"), **not yet run in CI.**
Applies to `roxygen-suggest.yml`, `test-suggest.yml` and
`authors-suggest.yml`. The analysis workflow
(`datashield-analysis-suggest.yml`) has its own push-on-plan model and
stays as it is.

## Why

Today the three workflows only work on pull requests (`changed` mode) and
as sweeps (`all` mode). On a push they misbehave:
- **Roxygen and tests:** the example callers' expression makes them sweep
  the whole package of `sweep-base` on every push. With an explicit
  `scan-mode: changed`, `git diff origin/...HEAD` fails because there's no
  PR base.
- **Authors:** silently does nothing.
- **Self-trigger protection** checks `github.head_ref`, which is empty on
  a push, so with an App or PAT the bot's own pushes could start it again.

Pushing to a feature branch, with a `paths` filter, is a very likely way
for people to use these workflows.

## Decisions

### 1. Review what's new since the last run

| Event | Reviewed |
|---|---|
| PR opened or reopened | all files (authors: all commits) of the PR, as today |
| new push to an open PR (`synchronize`) | only the files/commits of that push (`before..after` in the PR event) |
| push without a PR | only the files/commits of that push (`before..after`) |
| push that creates a branch (`before` is all zeros) | the commits that exist on no other branch (`git log <after> --not` the other remote branches) |
| force-push that rewrites history | the difference between the old and new state (`before..after`) |
| schedule or manual run (sweep) | everything, as today |

`dev` plays no role in push and PR runs, however far the branch is ahead
of or behind it (the user's requirement). The caller's `paths` filter
decides whether a run starts at all; the workflow then takes the push's
changed files, filtered to `R/*.R` (roxygen, tests) as today.

**"Since the last run" needs a starting point:**
- **While a bot PR is open:** its description carries a hidden marker
  `<!-- bot-suggest: reviewed up to <sha> -->`, and the run reviews from
  there to now. That catches up runs that were dropped or failed in
  between. The marker is updated on every run, also when there's nothing
  new to suggest. Today the commit action only rewrites the description
  when there's a report, which must change.
- **No bot PR open** (none yet, merged or closed): from the event's
  `before` (push, PR `synchronize`), or the whole PR (opened).
- **The marker disappears with the bot PR** when it is closed: nothing to
  clean up, nothing stored in the repo.

Rejected: a hidden Git ref per branch (`refs/bot-suggest/reviewed/…`).
It would clutter the repo, need cleanup, and isn't needed once the bot PR
is closed (the user's point). Also rejected: GitHub's run history via the
Actions API, which would close the gap below but needs `actions: read`
from every caller.

**Accepted gap** (the user's decision): while no bot PR is open, a
dropped run's push isn't caught up. GitHub keeps one running and one
waiting run per concurrency group; a third quick push replaces the
waiting one, so the middle push's files aren't reviewed until they change
again, or until a sweep. A failed run is visible and can be re-run (same
`before`). The outcome is a missing review, not a wrong suggestion.

Rejected alternative: on a push, review everything the branch changed
relative to a `compare-base` (like a PR into `dev`). It is consistent with
today's PR mode, but the user wants only what is new in the push.

### 2. The bot branch is built on, not rebuilt

Today `commit-updated-files` (`changed` mode) rebuilds
`bot-suggest/<kind>/<branch>` from the branch head and force-pushes it.
Under decision 1 that would lose unmerged suggestions of earlier pushes,
because their files aren't reviewed again. New behaviour, when an open
bot PR exists for the branch:
1. check out its branch;
2. merge the current branch head into it, the user's version winning on
   conflicts (`-X theirs` from the bot branch's point of view);
3. add this run's suggestions as per-file commits;
4. push without force.

The result is one bot PR per branch that collects suggestions until it is
merged or closed. The common case "push a file, keep working on it, push
again before looking at the bot PR" works by itself: the file is in the
new push, it's reviewed again against the current code, and its new
suggestion replaces the old one. If the merge can't be resolved
automatically, that run falls back to rebuilding the branch, with a note
in the PR description.

Setting `open-suggestion-pr: add | replace` (default `add`), so the user
can switch to "replace" after the first real tests without a code change.

Options considered:
- one bot PR per push: many PRs, and older ones conflict;
- wait until the open bot PR is handled: pushes in between get no review.

### 3. Push and PR runs can't collide

A caller triggering on both push and `pull_request` (a push to a branch
with an open PR) would start two runs writing the same bot branch. So:
- one concurrency group per branch, shared by both triggers:
  `<workflow>-<repo>-<head branch>`, with `github.head_ref ||
  github.ref_name`. Runs queue (`cancel-in-progress: false`) rather than
  cancel each other. GitHub keeps only one waiting run per group, see
  the accepted gap above;
- self-trigger protection on `github.head_ref || github.ref_name`
  starting with `bot-suggest/`, so it holds for pushes too.

### 4. Mode by event

`scan-mode: auto` (new default): PR or push → changed; schedule or manual
run → sweep. `changed` and `all` stay available. The example callers no
longer need the `github.event_name == 'pull_request' && …` expression.

### 5. Branch inputs

- **Push and PR runs need no branch input:** the branch comes from the
  event, and the bot PR targets that same branch.
- **`sweep-base`, new default empty:**
  - manual run → the branch chosen in the "Run workflow" menu;
  - scheduled run → `dev`, since a schedule always starts on the default
    branch, usually `main`;
  - set explicitly → always that branch. Projects without `dev` set
    `sweep-base: main` once.

  **Behaviour change:** a manual run sweeps the chosen branch, not always
  `dev`. GitHub preselects the default branch (usually `main`) in that
  menu. Mention it in the docs and the release note.

### 6. Sweep branch names include the base

`bot-suggest/<kind>-sweep-<base>-YYYY-MM` (e.g.
`bot-suggest/docs-sweep-ci-workflow-2026-10`) instead of
`bot-suggest/<kind>-sweep-YYYY-MM`. Today sweeps of two different bases in
the same month would overwrite each other's branch and PR.

### 7. Authors on push too

`authors-suggest.yml` follows the same model (user's choice, for
consistency): PR opened → all PR commits; further push → its commits;
plain push → its commits. There's no Claude call, so it's cheap. It's
harmless when nothing is new: already-listed authors change nothing,
e.g. when a merged PR's commits reach `dev` again by push. Callers still
trigger it without a `paths` filter.

### 8. Test history evidence

`build_test_evidence()` compares a function with its earlier state to
tell an intended change from a bug. Its base becomes the state before the
run's changes: `before` for a push or a PR `synchronize`, the PR base for
an opened PR.

### 9. Commits that aren't new although they're in the push

- **Merging `dev` (or another branch) into the branch:** the push carries
  others' commits. Only commits that exist on no other branch count. This
  is the same rule as for a new branch, applied to every push, so others'
  changes aren't reviewed or credited.
- **Merging the bot's own suggestion PR:** a push with the bot's commits.
  Commits that came from a `bot-suggest/` branch are left out,
  recognised by:
  - the bot author (`config/bot-authors.json`);
  - the commit-message prefixes (`commit-prefix` of the commit action);
  - "Merge … from …/bot-suggest/…".

  The author alone isn't enough: with a PAT the merge carries the user's
  name.
- **Rebase plus force-push:** the user's commits get new IDs and are
  reviewed again (acceptable). The bot branch is based on the old
  history, so it can't be built on. If the marker's commit (or `before`)
  isn't an ancestor of the new head, that run rebuilds the bot branch
  (`replace`); its suggestions come back because the files are reviewed
  again.

### 10. Events that do nothing, with one clear log line

- **Branch deleted:** GitHub sends a push event with `deleted: true`.
- **Tags pushed:** a push trigger without a `branches` filter also fires
  on tags (`refs/tags/…`).
- **PRs from forks:** no secrets and no OIDC token, so Claude can't be
  reached, and the bot can't push to the fork. This already fails today;
  now it gets a clear message.
- **Dependabot PRs:** no secrets, same reason.

### 11. Draft PRs

Reviewed like any PR, as today (the user's decision). It fits "push and
keep working".

## Implementation (2026-10-01)

- **`.github/actions/resolve-suggestion-scope/`** (action, runs before
  checkout): `resolve-suggestion-scope.sh` decides skip / mode / branch
  from the event (decisions 4, 5 and 10). Next to it,
  `determine-changes.sh`, called from the `.shared-workflows` checkout
  after checkout, works out what is new (decisions 1 and 9):
  - **Starting point:** the marker, else the PR base (opened), else
    `before`, else commits on no other branch.
  - **Filter:** `--no-merges`, `--not` the other remote branches (not
    for an opened PR), bot authors and bot commit subjects
    (`bot_commit_subjects` in `config/bot-authors.json`).
  - **Output:** `files_to_check.txt`, `commits.txt`; `count`, `base_rev`,
    `rebuild`, `reviewed_sha`.
- **`commit-updated-files`:** new inputs `reviewed-sha`,
  `open-suggestion-pr` and `rebuild`. In `changed` mode an open bot PR is
  built on:
  - the merge uses `-X theirs`, then the run's files are put on top and
    pushed without force;
  - each run's report is appended as "Update for <sha>", the oldest
    updates dropped near GitHub's size limit;
  - the marker is updated, also without new suggestions;
  - fallback to a rebuild with a note.

  Sweep branches include the base. The analysis workflow passes
  `open-suggestion-pr: replace` (its model regenerates unmerged steps
  anyway).
- **Workflows** (roxygen, tests, authors):
  - the scope step first, checkout of `ref`, then the files/commits step;
  - later steps run if `count > 0`;
  - one concurrency group per branch;
  - `scan-mode` default `auto`, `sweep-base` default empty, new input
    `open-suggestion-pr`;
  - authors with `allow-sweep: false`.
- **R:**
  - `suggest_authors.R` reads `commits.txt`;
  - `suggest_tests.R` and `build_test_evidence()` use `BASE_REV` (the
    state before the changes) instead of the PR base branch;
  - the test prompt says "the changes under review" instead of "this pull
    request".
- **Examples:** no `scan-mode` expression any more; a commented-out
  `push` trigger (`branches-ignore: [main]`).

**Tested locally:**
- **Scenarios 1–8 in a sandbox:**
  - a new branch with 2 commits;
  - a second push (only the new file; the bot PR keeps the earlier
    suggestions, the report is appended, the marker moves);
  - merging `dev` (0 new commits);
  - working on a file with an open suggestion (merged with the user's
    version winning, then a new suggestion);
  - merging the bot PR (0 new);
  - a new bot PR, then amend + force-push (rebuild with a note);
  - PR opened (the whole PR);
  - a modify/delete conflict (fallback with a note).
- **Scope decisions** for 16 event cases.
- **Sweep branch name** with the base, and `replace`.
- **`build_test_evidence()`** with and without a base.

Found and fixed while testing: `grep` with no match under `pipefail` ended
`determine-changes.sh` on every first run.

## Consequences for callers

- **PR runs review less:** after the first run, only the new push's
  files. A deliberate "review everything again" is a manual run (sweep) on
  the branch.
- **Manual runs sweep the selected branch** (decision 5).
- **Sweep branch and PR names change** (decision 6); an open sweep PR of
  the current month is then left behind once.
- **Example callers get simpler** (`scan-mode: auto`). Callers may add
  `push` triggers (with `branches` / `paths` filters), keeping pushes to
  `main` out via `branches`.

None of this needs new permissions or secrets.

## Open points

- **Fewer repeated reviews:** skipping functions whose code didn't change
  since their last review (a hash, like the analysis workflow's markers)
  could cut cost further. Not in the first version.
- **Testing:** PR mode is confirmed in CI (dsSupportClient PR #21 /
  #24), so the unified model must be re-tested there:
  - PR opened, then further pushes;
  - push without a PR;
  - push to a new branch;
  - push and PR at the same time;
  - an open bot PR with a conflicting change;
  - merging `dev` into the branch;
  - merging the bot PR;
  - rebase plus force-push;
  - branch deletion and tag pushes;
  - three quick pushes with a bot PR open, which the marker must catch up.
- **Docs pending when built:** the trigger section of the three pages,
  examples, the suggestions page (sweeps, bot branches), and a release
  note for the behaviour changes.
