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
   looks for `tests/testthat/test-<function>.R`.
2. `has_adequate_coverage()` skips functions that already look tested
   (placeholder heuristic, see open questions).
3. For DataSHIELD client packages, `detect_dslite_setup()` checks for an
   existing DSLite `tests/testthat/setup.R`.
4. `ask_claude_for_tests()` (profile `test-review`, prompt
   `prompts/test-review-prompt.md`, guidance `config/test-role-guidance.json`)
   returns up to 5 tests as fields — description, setup code, assertions —
   never assembled `test_that()` code.
5. `assemble_test_block()` builds the blocks; if a fresh DSLite setup is
   needed, `ensure_dslite_setup_file()` writes `setup.R` for the dataset
   Claude picked.
6. `write_test_blocks()` + `run_test_blocks()` write all candidates and run
   the file with the package loaded from source.
7. The file is rewritten as *original content + passing tests only*. A
   generated `setup.R` is kept only if at least one test passed.
8. Each failing **generated** test goes to `ask_claude_to_classify_failure()`
   (profile `test-failure-classification`):
   `bad_test` / `env_misconfiguration` → PR comment; `real_bug` → GitHub issue.
9. Written files are listed in `updated_files.txt`; the
   `commit-updated-files` action commits them.

Trigger modes: `changed` (PR — new/modified functions only; commits go to
`bot-suggest/tests/<PR branch>`, opened as a sub-PR into the PR branch
with a link comment on the originating PR) and `all` (sweep — whole
package, opens a PR against `dev`).

## Design decisions

- **Real tests, not stubs.** Runnable `test_that()` blocks with genuine
  assertions — highest value, accepted risk.
- **Never touch existing tests.** Only append, or create the test file.
- **Max 5 tests per function**, enforced by the tool schema (`maxItems`),
  not by prompt wording.
- **Every test is run before it's trusted.** Tests can be checked
  mechanically; docs can't — use that.
- **A failure is never silently kept or dropped.** Three causes are kept
  apart: bad test, real bug caught, broken environment. Classification
  happens *after* the run, from the actual failure output. Real bugs get an
  issue because it outlives the PR.
- **Only generated tests are judged.** Pre-existing tests in the same file
  are run too, but their failures are not classified.
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

**Dataset selection:** an existing DSLite `setup.R` is always reused as-is
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
alone; commit action in both modes. **Never run in real CI yet.**

Caller requirements: `datashield`/`datashield-type` inputs, App secrets
(so the suggestion PR triggers required checks), `issues: write`, and the three
`anthropic-*` secrets, with a federation rule for `test-coverage-suggest.yml`. No shared
`concurrency` group with `roxygen-suggest.yml` is needed any more: each
pushes to its own `bot-suggest/<kind>/…` branch, never the PR branch.

## Open questions

- **Real coverage data.** `has_adequate_coverage()` only checks whether an
  existing test file mentions the function name. Preferred replacement:
  per-function coverage (`covr::function_coverage()`) captured by
  `R-CMD-Check.yml` and handed over, instead of a second install + test run.
  Handoff mechanism not designed yet.
- **Changed-function detection.** `changed` mode reuses roxygen's
  `git diff` of `R/*.R` against the PR base — confirm that's the right
  scope for tests.
- **CRAN compliance** of generated tests: deliberately out of scope for now.
