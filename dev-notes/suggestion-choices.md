# Choosing suggestions by checkbox (design, not built)

Agreed with the user on 2026-10-02 (dsAnalysis session): the most
user-friendly way to take some of a bot PR's suggestions and leave
others. Until now that meant editing files on the bot branch by hand, or
reverting commits with git — and a file often mixes wanted and unwanted
changes.

## The idea

The bot PR's description lists every suggestion that changes a file as a
checkbox. The user unticks what they don't want (or ticks a suggestion
that wasn't applied), and a workflow rebuilds the bot branch from the
ticked items. No Claude call, no git, all in the browser.

## Decisions (proposed)

1. **What gets a checkbox** — every item that changes a file:
   - tests: a new test (`new`), an updated or deleted existing test
     (`updated`, `deleted`) — ticked;
   - roxygen: an applied change per field (`applied`: title, description,
     each `@param`, …) — ticked; a suggestion that wasn't applied
     (`dropped`, its reason isn't accepted) — unticked, ticking applies it;
   - generated setup files (`setup`) — ticked, unticking removes the file
     (only if no ticked test needs it).
   Notes, possible bugs and failed tests stay plain list items.
2. **Where:** in the description, next to each item's existing report
   line, as `- [x] … <!-- id:E12 -->` (the hidden id ties the box to its
   state entry). One place, already rebuilt from the state on every run.
3. **New reusable workflow `suggestion-choices.yml`** plus a caller in each
   repository: `on: pull_request: types: [edited]`, running only for
   `bot-suggest/roxygen/*` and `bot-suggest/tests/*` heads, and only when a
   person edited the description (`github.event.sender.type != 'Bot'`;
   the bots' own edits with the App token would otherwise trigger it).
   Concurrency: the same group as that bot's runs for the PR's base
   branch (`roxygen-suggest-<repo>-<base>` / `test-suggest-<repo>-<base>`),
   so a choice and a bot run never write the bot branch at the same time.
4. **What it does:** compares the boxes with the state; for each changed
   item it edits the files on the bot branch, starting from their current
   bot version (so the user's own edits stay):
   - new test unticked → remove its `test_that()` block; ticked again →
     put the block back, taken from the bot branch's history (the commit
     that proposed it);
   - updated test unticked → the block from the base branch; deleted test
     unticked → re-insert the base branch's block;
   - roxygen field unticked → the field from the base branch; ticked →
     the field from the entry's `proposed` text (already in the state);
   - setup file unticked → delete it.
   Then one commit ("chore: apply suggestion choices"), the state's
   statuses updated (`declined` / `active`), and the description
   refreshed. Nothing changed → nothing done.
5. **The bots respect the choices:** each bot run reads the boxes before
   it rewrites the description, so a choice made while it runs isn't lost,
   and doesn't propose a declined item again — a declined test (same R
   file and description) or roxygen field (same file and field) stays
   declined until the function's code changes.
6. **Merging too early:** the workflow sets a commit status ("suggestion
   choices: applying" → "applied") on the bot PR's head, so a merge right
   after unticking shows that the branch isn't up to date yet.

## Open points

- Re-ticking a new test after a later bot run rewrote the file: the block
  is looked up by description in the bot branch's history; if it can't be
  found, the box is unticked again with a note.
- The authors bot's PRs stay as they are (one DESCRIPTION change each).
