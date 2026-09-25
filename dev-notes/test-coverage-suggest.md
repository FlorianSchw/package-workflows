# test-coverage-suggest.yml

Reusable workflow that finds under-tested functions in an R package, asks
Claude to draft real testthat tests for them, **runs every generated test**,
and proposes only the ones that pass. Failing candidates are classified and
surfaced for a human instead of being kept or discarded silently.

Sibling of [roxygen-suggest.yml](roxygen-suggest.md); shares its auth,
config and R conventions (see `CLAUDE.md`).

## How it works

Entry script: `R/suggest_tests.R`. Per function file in `files_to_check.txt`:

1. `parse_r_file()` → function name + source; `find_existing_test_file()`
   looks for `tests/testthat/test-<function>.R`; `parse_test_file()` finds
   its `test_that()` blocks (R's parser; only uniquely named blocks on
   their own lines are editable).
2. Every function is reviewed, tested or not (see
   [suggestion-thresholds.md](suggestion-thresholds.md)); a sweep selects
   which functions (see "Sweep scope" below).
3. The existing tests are run first (`run_test_blocks()`), and
   `build_test_evidence()` collects the history: last change of function
   and test file, which changed later, and in a PR whether the PR changed
   the function without its test, plus the function's diff.
   Once per run, `summarize_test_data()` runs the setup/helper files in a
   separate R process (`collect_test_data()`: package loaded from source,
   files sourced from `tests/testthat/` like testthat does) and describes
   the data tables they create — tables inside any DSLite server (read via
   a temporary DSLite session), else plain data frames: rows, columns,
   types, missing values, factor level counts. No other values. A file
   failing partway still yields the tables created before, with a note.
4. For DataSHIELD client packages, `detect_dslite_setup()` checks for an
   existing DSLite setup in any `tests/testthat/setup*.R` / `helper*.R`;
   those files go to Claude verbatim (objects, symbols, helpers).
5. `ask_claude_for_tests()` (profile `test-review`: Opus 5 with adaptive
   thinking; prompt `prompts/test-review-prompt.md`, guidance
   `config/test-role-guidance.json`) returns fields only, never assembled
   `test_that()` code: up to `max_new_tests` new tests (description,
   reason, setup code, assertions) and decisions on existing tests
   (update / delete / report, with reason and explanation).
6. `filter_generated_tests()` applies the threshold to new tests,
   `review_existing_tests()` the safeguards to the decisions (see Design
   decisions). `assemble_test_block()` builds the blocks; if a fresh DSLite
   setup is needed, `ensure_dslite_setup_file()` writes `setup.R` — or
   `setup-dslite.R` if a `setup.R` without DSLite already exists, so that
   file is never touched. *Revisable (2026-09-25):* `setup.R` first to
   avoid cluttering packages with files; revisit after feedback.
7. `rewrite_test_content()` builds a candidate file (updates in place,
   deletions, new tests appended; everything else line for line),
   `write_test_file()` writes it and `run_test_blocks()` runs it with the
   package loaded from source.
8. The file is rewritten from the *original* with only what passed: failed
   new tests are left out, a failed update keeps the original test and is
   reported. A generated DSLite setup is kept only if a new test passed.
9. Each failing **new** test goes to `ask_claude_to_classify_failure()`
   (profile `test-failure-classification`):
   `real_bug` → GitHub issue; `bad_test` / `env_misconfiguration` → PR
   comment, or in a sweep into the report.
10. If new tests were kept, `ensure_testthat_setup()` makes sure R CMD
    check runs them: creates `tests/testthat.R`, adds testthat to
    `Suggests`, and sets `Config/testthat/edition: 3` (edition only when
    the runner is created fresh — an existing suite's edition stays).
11. Written files are listed in `updated_files.txt`; the
    `commit-updated-files` action proposes them. `format_test_summary()`
    gives a one-line statistic (new / updated / deleted tests, DSLite and
    testthat setup created) for the link comment on the originating PR
    (`suggestion_summary.md`) and the top of the PR description.
    `publish_test_report()`
    puts changes to existing tests (with reasons), reported tests and
    sweep failures into the suggestion PR's description — or, without a
    suggestion PR, a PR comment (sweep: one issue).

Trigger modes: `changed` (PR — new/modified functions only; commits go to
`bot-suggest/tests/<PR branch>`, opened as a sub-PR into the PR branch
with a link comment on the originating PR) and `all` (sweep — opens a PR
against `sweep-base`).

**Sweep scope:** a sweep doesn't review every function every month. It
takes functions whose file or test file changed within
`sweep-lookback-days` (default 35), plus a rotating share of the rest —
picked by a stable hash of the file name — so each function comes up at
least once per `sweep-rotation-months` (default 6; `0` = all functions
every sweep). Saves Claude calls without lowering quality per call.

## Design decisions

- **Real tests, not stubs.** Runnable `test_that()` blocks with genuine
  assertions — highest value, accepted risk.
- ~~**Never touch existing tests.** Only append, or create the test file.~~
  Revised 2026-09-25 (PR #21 showed why: an outdated test left R CMD check
  red, with a human needed for every such case): existing tests are
  reviewed — updated, deleted or reported — under the safeguards in
  [suggestion-thresholds.md](suggestion-thresholds.md). Key rule: a
  failing test is never adapted to output that may be wrong.
- ~~**Max 5 tests per function**~~ Now `max_new_tests` (default 10) in
  `config/claude.yml` — 5 was too few to check real behavior. Enforced by
  the tool schema (`maxItems`), not by prompt wording.
- **Every test is run before it's trusted.** Tests can be checked
  mechanically; docs can't — use that.
- **A failure is never silently kept or dropped.** Three causes are kept
  apart: bad test, real bug caught, broken environment. Classification
  happens *after* the run, from the actual failure output. Real bugs get an
  issue because it outlives the PR.
- ~~**Only generated tests are judged.**~~ Pre-existing tests are run
  before any change and their results — with the history evidence — go to
  Claude, which decides on them; failures of new tests are classified as
  before.
- **Passing tests are proposed, not pushed** — via a sub-PR into the PR
  branch, like roxygen suggestions, so the PR author has the final say.

## DataSHIELD client packages: DSLite

Server-side packages are tested like any R package. Client-side functions
need a DataSHIELD server, so tests run against **DSLite** — an in-process
server implementation — with real execution, no mocking.

Verified pattern (what `ensure_dslite_setup_file()` generates):

```r
logindata <- DSLite::setupCNSIMTest(packages = c("<client package>"))
conns <- DSI::datashield.login(logins = logindata, assign = TRUE)
# tests use `conns`; the dataset is assigned on every study as "D"
```

**Dataset selection:** an existing DSLite setup (any `setup*.R` / `helper*.R`) is always reused as-is
(e.g. from `DSFunctionCreator::init.dsTest()`). Otherwise Claude picks one
of DSLite's five bundled datasets, listed with descriptions in
`config/dslite-canned-datasets.json`:

| Name | Rows/study | Fits |
|---|---|---|
| CNSIM | 2163 | default: health-style numeric/binary columns |
| DASIM | 10000 | same shape, larger sample |
| DATASET | 71 | types, NA/NULL, value-range edge cases |
| DISCORDANT | 12 | paired concordance comparisons |
| SURVIVAL | 2060 | time-to-event analysis |

The `dslite_dataset` enum in the tool schema is built from the same file,
so it can't drift from what the prompt offers. `datashield-example-env.json`
is **not** used here — it describes the real Opal demo server for roxygen
usage examples, a different scenario.

**Server methods come from the installed *server* package.** DSLite builds
its method table by scanning installed packages for `inst/DATASHIELD`; only
server packages (e.g. `dsBase`, `dsTidyverse`) ship one. The `packages =`
argument above is only a `requireNamespace()` check. So in CI the client's
`DESCRIPTION` must list its server packages (plus `DSLite`, `testthat`),
e.g. under `Suggests`, for `needs: check` to install them — otherwise every
DSLite test fails with an unregistered-method error.

Pitfalls found while building this:
- `.prepare_dslite()` (seen in `dsTidyverseClient`'s tests) is a private
  helper of that package, not a DSLite API.
- Tests must run with the package loaded (`load_package = "source"`);
  without it every test fails in CI with "could not find function".
  pkgload registers the namespace before `setup.R` runs, so this also works
  for a client package that isn't installed.

## Status

Verified locally (real entry script, only the Anthropic/GitHub APIs mocked):
plain package; DataSHIELD client package that is not installed, fresh
DSLite setup, pass + fail; all-fail cleanup; pre-existing failing test left
alone; commit action in both modes. First real CI run on dsSupportClient
PR #18 (`changed` mode): auth and the full job ran, but no tests were
generated. ~~Test execution, failure classification and the sub-PR are
still unconfirmed in CI.~~ Confirmed on PR #21 (with the threshold code):
passing tests for `ds.wrapper` (already tested) and `ds.tableBatch`
proposed in sub-PR #24, a failing one classified `bad_test` and commented
on #21, and a later push updated #24 instead of opening a second PR. Not
yet seen: deletion notes, `real_bug` issues, sweeps.

Caller requirements: `datashield`/`datashield-type` inputs, App secrets
(so the suggestion PR triggers required checks), `issues: write`, and the three
`anthropic-*` secrets, with a federation rule for `test-coverage-suggest.yml`. No shared
`concurrency` group with `roxygen-suggest.yml` is needed any more: each
pushes to its own `bot-suggest/<kind>/…` branch, never the PR branch.

## Open questions

- **Real coverage data.** Every function is now reviewed and Claude decides
  whether tests add value (see [suggestion-thresholds.md](suggestion-thresholds.md)).
  Per-function coverage (`covr::function_coverage()`) captured by
  `R-CMD-Check.yml` and handed over, instead of a second install + test run,
  would still help: as the coverage gain per generated test, and as a hint
  to Claude about uncovered lines.
  Handoff mechanism not designed yet.
- **Changed-function detection.** `changed` mode reuses roxygen's
  `git diff` of `R/*.R` against the PR base — confirm that's the right
  scope for tests.
- **CRAN compliance** of generated tests: deliberately out of scope for now.
