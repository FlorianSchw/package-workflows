# Choosing suggestions by checkbox (built 2026-10-04)

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

## Decisions

The user chose the recommended option for each open question: declined
suggestions are remembered until the code changes, not-applied roxygen
suggestions can be ticked to apply them, and a commit status guards
against merging too early.

1. **What gets a checkbox** (`suggestion_choice()`) — every finding that
   changes a file and is still open:
   - tests: a new test (`new`), an updated or deleted existing test
     (`updated`, `deleted`) — ticked;
   - roxygen: an applied change per field (`applied`: title, description,
     each `@param`, …) — ticked; a suggestion that wasn't applied
     (`dropped`, its reason isn't accepted) — unticked, ticking applies it
     (the finding then becomes `applied`).
   Generated setup files, notes, possible bugs and failed tests stay plain
   list items.
2. **Where:** in the description, as the report line itself:
   `- [x] … _(sha)_ <!-- choice:E12 -->` (`choice_line()`); the hidden id
   ties the box to its finding. A declined one reads
   `- [ ] … _(sha · declined)_`. Section counts leave declined ones out.
3. **The choice is a field, not a status:** `choice` (TRUE/FALSE) on the
   finding, recorded from the boxes by `record_suggestion_choices()`;
   without it the default applies (applied kinds ticked, `dropped`
   unticked). A declined finding stays `active`, so it can be ticked
   again.
4. **Workflow `suggestion-choices.yml`** plus a caller in each repository
   (`examples/suggestion-choices.yml`): `on: pull_request: types:
   [edited]`, only for `bot-suggest/tests/*` and `bot-suggest/docs/*`
   heads, and only when a person edited the description
   (`github.event.sender.type != 'Bot'`; the bots' own edits with the App
   token would otherwise start it again). Concurrency: the same group as
   that bot's runs for the PR's base branch (`test-suggest-<repo>-<base>`
   / `roxygen-suggest-<repo>-<base>`), so a choice and a bot run never
   write the bot branch at the same time.
5. **What it does** (`R/apply_suggestion_choices.R`): for every finding
   that is a choice, it makes the files match the box, **checking what
   they contain** rather than what changed since last time — so it doesn't
   matter whether it or a bot run comes first:
   - tests (`apply_test_choice()`): new test ticked → the block is in the
     file (put back from the bot branch's history,
     `test_block_from_history()`), unticked → it isn't; updated test
     ticked → the bot's version, unticked → the base branch's; deleted
     test ticked → gone, unticked → the base branch's block is back. A
     test file the bot created that has no test left is removed.
   - roxygen (`apply_roxygen_choice()`): ticked → the field has the
     `proposed` text, unticked → the base branch's field, or none if the
     base branch has none (`replace_roxygen_field()`, which inserts a new
     field by `tag_order`).
   Then one commit ("chore: apply suggestion choices") and the description
   rebuilt: the bot's intro, its "Latest review" line and the hidden
   markers stay. A choice that can't be applied (the block can't be found
   any more, no stored proposal) is set back, with a note.
6. **The bots respect the choices:** each bot run records the boxes before
   it rewrites the description, so a choice made in between isn't lost.
   A declined test (same function and test name, also for updates and
   deletions) or roxygen field (same file and field) isn't proposed again
   while the function's code (`code_fingerprint()` of `fn_source()`,
   stored with each finding as `code`) is unchanged; once it changes, the
   declined finding is crossed out ("declined, but the code changed
   since") and may come back (`declined_suggestions()`).
7. **Merging too early:** the workflow sets a commit status
   ("suggestion choices": pending → success, or failure) on the bot PR's
   head, so a merge right after changing a box shows that the branch
   isn't updated yet.

## Tested

Locally (2026-10-04) in a fixture repository with a base branch and a bot
branch: unticking a new test and an update, ticking the new test again
(restored from history), unticking an applied title and an added
`@return`, ticking a not-applied `@param` suggestion; a second run with
the same boxes changes nothing. The declined memory: same fingerprint →
still declined, changed code → released. Not yet run in GitHub Actions.

## Open points

- Findings stored before this change have no `proposed` text for applied
  roxygen changes and no `code`: re-ticking such a declined change isn't
  possible (the box is set back with a note), and its memory has no
  fingerprint to compare (it stays declined until a bot run stores one).
- The authors bot's PRs stay as they are (one DESCRIPTION change each).
