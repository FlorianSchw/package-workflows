# Suggestion thresholds

When is a change by the roxygen or test suggestion workflow worth a pull
request? This note records the current answer. It is a **revisable
decision** (made 2026-09-25), expected to be tuned once there is data on
which suggestions get merged.

## Principle

Same as everywhere in these workflows: don't trust prompt wording where a
structural rule is possible.

1. **Claude states a reason for every change, from a fixed list** (tool
   schema enum). The list includes honest "not really an improvement"
   options (`clarity`, `style`, `other`): a model with a place for that
   case uses it more reliably than one told "don't make style changes".
2. **R keeps only accepted reasons.** The accept lists live in
   `config/claude.yml` (`accept_reasons` per profile), so a repository can
   tune them by overriding that file, without touching prompts.
3. **Mechanical filters in R** on top, independent of what Claude says.

## Current settings

### Roxygen (`roxygen-review`)

| Reason | Meaning | Proposed? |
|---|---|---|
| `missing` | Field absent or a placeholder | yes |
| `inaccurate` | Contradicts the code | yes |
| `incomplete` | Misses something the code does | yes |
| `clarity` | Correct and complete, could be clearer | no |
| `style` | Formatting or wording only | no |

Mechanical filter: a change whose text differs from the existing one only
in whitespace, punctuation or case is dropped. A field Claude changed
without listing it in `changes` is not applied either. Rejected fields
keep their **original lines byte for byte**; a file is only rewritten if at
least one change is accepted. (`accepted_roxygen_fields()`,
`build_roxygen_block()`.)

### Tests (`test-review`)

| Reason | Meaning | Proposed? |
|---|---|---|
| `uncovered_branch` | A code path no existing test reaches | yes |
| `error_handling` | An error or warning the function raises | yes |
| `edge_case` | Unusual but valid input (NA, empty, boundaries) | yes |
| `regression` | Pins down behaviour likely to break on change | yes |
| `other` | None of these | no |

Mechanical filter: a test whose assertions already exist verbatim in the
test file (ignoring whitespace) is dropped. And, as before, only tests that
pass a real run are proposed. (`filter_generated_tests()`.)

**Every function is reviewed**, in PRs and in sweeps, whether it already
has tests or not — the old "test file mentions the function name → skip"
heuristic is gone. Claude decides whether new tests add value; the
threshold above decides what is proposed. At most 5 new tests per function
and run.

### Existing tests that could be deleted

Claude may list existing tests as `duplicate`, `behavior_removed` or
`trivial`, with an explanation. They are **never deleted automatically**;
only entries naming a test that actually exists in the file are kept.
They are reported:

- in the suggestion PR's description, if new tests were proposed;
- otherwise as a comment on the originating PR (sweep: in the sweep PR's
  description, or one issue if no sweep PR opens).

## Revisit when

- Suggestions of an accepted category keep getting closed, or rejected
  categories are missed in review → change the accept lists.
- Sweeps keep adding tests to the same functions month after month → the
  bar for tests is too low.

## Ideas not implemented yet

- **Log the reason of every suggestion** and compare with merged vs. closed
  suggestion PRs after a few weeks, to set the accept lists from data
  instead of guesses.
- **Coverage gain per generated test** (`covr`), shown in the suggestion PR
  — an objective signal. Not a hard filter: edge-case tests often add no
  line coverage and are still valuable.
- **Give Claude the diff of the changed function** in PR runs, if
  suggestions turn out to be unfocused.
