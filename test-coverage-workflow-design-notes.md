# Design notes: test/coverage suggestion workflow

## STATUS: decisions locked in — implementation starting

This is a planned sibling to the already-built `roxygen-suggest.yml` workflow
in `package-workflows`. Same overall shape (LLM-assisted, WIF-authenticated,
deterministic assembly), applied to unit tests and coverage instead of
documentation. Read `roxygen-suggest.yml`, `R/suggest_roxygen.R` and
`R/functions/`, and its config files (`config/roxygen-style.json`,
`config/datashield-example-env.json`, `config.yml`) before touching this —
several patterns and possibly literal logic should be reused, not rebuilt.

Note: `roxygen-suggest.yml` itself has evolved since this doc's original
draft — it now commits suggestions directly to the PR branch (via a
`resolve-push-token` composite action + `docs_updated_files.txt`), not PR
review-comment suggestion boxes. Any reuse of that pattern here should follow
the *current* `roxygen-suggest.yml`, not the older suggestion-comment
approach described in earlier revisions of this doc.

## GOAL

Look at a package's functions, unit test coverage (testthat), and suggest
new tests for under-tested functions. CRAN-submission compliance for the
test framework itself is a real future concern but explicitly **not** the
focus right now — deferred to later.

## DECIDED SO FAR

- **Full test implementations, not just stubs or flagging.** Florian
  explicitly wants Claude to draft real, runnable `test_that()` blocks with
  real assertions — the highest-value but highest-risk of the three tiers
  discussed (flag-only / stub-generation / full implementation). Chosen
  deliberately, accepting the risk, because it's judged genuinely
  achievable.
- **Never touch existing tests.** Only append new `test_that()` blocks, or
  create a new `test-<function>.R` file if none exists for that function.
  Existing test code is never rewritten or even shown to Claude as
  editable — same "carry forward untouched" principle already used for
  `@export`/`@import`/`@importFrom`/`@author` in the roxygen workflow.
- **Hard cap on generated tests per function: 5.** Enforced via the tool
  schema itself (an array with `maxItems: 5`), not just a prompt
  instruction — same reasoning as why roxygen suggestions moved to
  forced-field output instead of free text: don't trust an instruction
  where a structural constraint is available instead.
- **Every generated test must actually be run before being trusted.** This
  is a real advantage tests have over documentation — a test either passes
  or fails mechanically; there's no equivalent check for "is this roxygen
  description accurate." A generated test that errors or fails should
  never be silently committed.
- **A failing generated test is NEVER silently discarded or silently kept.**
  There are (at least) three distinct reasons a generated test could fail,
  and they must not be treated the same:
  1. The test itself is wrong (bad assertion, misunderstood behavior).
  2. The test is right and it caught a **genuine bug** — discarding this
     silently would mean the tool could stumble onto a real defect and
     throw the discovery away.
  3. (DataSHIELD-specific, see below) The test environment itself is
     misconfigured — wrong dataset, unregistered server method — which is
     neither a bad test nor a real bug, just broken scaffolding.
  **Surfacing decided:** a bad test (1) or environment misconfiguration (3)
  gets a **PR comment** describing the failure and the generated test, for
  human judgment — nothing auto-applied. A genuine bug (2) gets a
  **separate GitHub issue** instead — more durable/trackable than a PR
  comment, and survives even if the PR itself is closed without the
  generated test being merged. The three-way classification itself (which
  of the three a given failure looks like) is an LLM judgment call made
  *after* the test fails, using the failure output, not guessed upfront.
- **Passing generated tests are committed directly**, mirroring
  `roxygen-suggest.yml`'s current behavior (not posted as suggestion
  comments) — same `resolve-push-token` / direct-commit-to-PR-branch
  pattern.

## SCOPE — locked in

**Both server-side and client-side (DSLite) support are built from the
start**, not phased — accepted the larger upfront design/implementation
surface (the DSLite config shape was the main open unknown, see below,
now resolved) rather than deferring client-side to a later phase.

## TRIGGER MODE — locked in

Mirrors roxygen's `changed`/`all` split, explicit purpose per mode (not
copied blindly):
- **`changed` (PR-triggered):** scoped to new/modified functions in that
  PR only — catches untested new code immediately, fast and reviewable.
- **`all` (sweep):** whole-package pass, catches pre-existing under-tested
  functions the PR-triggered mode would never touch on its own.

## REUSE FROM roxygen-suggest.yml — don't rebuild these

- **WIF authentication chain** — the OIDC → Anthropic token exchange,
  the per-repo federation rule, the `job_workflow_ref` claim scoping.
  Identical mechanism applies here.
- **`resolve-push-token` composite action** (`.github/actions/resolve-push-token/`)
  — App-token-if-configured, else `GITHUB_TOKEN`. Same need here: a
  generated-test commit needs to trigger downstream required checks the
  same way a doc-suggestion commit does. `roxygen-suggest.yml`'s current
  `Commit roxygen suggestions to PR branch` step (tracks changed files via
  a `docs_updated_files.txt`-style manifest, commits per-file, pushes with
  the resolved token) is the direct template for the equivalent
  test-commit step here.
- **Deterministic field-based assembly.** Claude should never freely
  produce final assembled code — same lesson learned the hard way in
  roxygen-suggest (two prompt-only attempts to stop duplicated/malformed
  output both failed; the fix was structural, not prompt wording). Claude
  should return discrete fields (test description, setup code, assertions)
  and the R script does the actual stitching into valid `testthat` syntax.
- **Sanitize + hard-fail pattern.** roxygen-suggest strips any leaked
  syntax artifacts from Claude's fields before assembly, and hard-fails
  loudly if a required field is empty after stripping, rather than
  silently shipping something broken. Same defensive posture likely
  belongs here.
- **"Run it and see, don't guess" debugging discipline** — repeatedly the
  right call in the roxygen workflow's history — surface raw errors/output
  rather than assuming behavior.
- **One function per file under `R/functions/`, loaded via `purrr::walk()`,
  `config.yml` for Claude call settings (with its own profile, e.g.
  `test-review:`, alongside `roxygen-review:`).** Direct structural
  precedent — same conventions, not a new pattern.
- ~~`server function called` identification... load-bearing here~~ —
  **turned out wrong, see DSLite section below.** DSLite auto-discovers
  server-side method registration from the client package name alone; no
  reuse of that roxygen extraction logic was needed after all.

## COVERAGE MEASUREMENT — integrate with R-CMD-Check.yml, don't duplicate

Coverage can't be judged by reading code — it requires actually running
the test suite. `R-CMD-Check.yml` already does this via `covr::codecov()`
(package-wide). Building a second, parallel pipeline that reinstalls the
package and reruns tests again would double CI cost for no reason.

Preferred direction: have `R-CMD-Check.yml` capture **per-function**
coverage (`covr::function_coverage()`, not just the package-wide
percentage) and hand that data to this new workflow/step, rather than a
fresh standalone job repeating the install + test run. Still needs actual
wiring — not built yet.

## DATASHIELD ROLE SPLIT — different from the roxygen version

For roxygen, the client/server split was mostly about *what to write*
(framing, whether a demo environment is relevant). For testing, it's a
genuinely different **testing strategy** per role, not just different
wording:

- **Server-side**: real local computation — straightforwardly testable in
  the normal R sense.
- **Client-side**: uses **DSLite**, not mocking. DSLite is a serverless,
  in-process implementation of the DataSHIELD server interface — it lets
  client functions be tested with **real execution and real assertions**,
  without needing a live Opal server.

  **The `.prepare_dslite(...)` pattern originally in this doc (copied from
  `dsTidyverseClient`'s own test files) turned out to NOT be a real DSLite
  API** — it's a private helper that package's own test suite defines
  internally. Confirmed by actually running it: `.prepare_dslite` is not an
  exported object from `namespace:DSLite`. The **real, verified-by-actual-
  execution** pattern, once `DSLite`/`dsBaseClient`/`dsTidyverseClient` were
  installed locally for testing:

  ```r
  library(DSLite)
  library(dsTidyverseClient)

  logindata <- setupCNSIMTest(packages = c("dsTidyverseClient"))
  conns <- datashield.login(logins = logindata, assign = TRUE)

  test_that("ds.arrange sorts without error and returns a data.frame", {
    ds.arrange(df.name = "D", tidy_expr = list(LAB_TSC), newobj = "sorted_df", datasources = conns)
    expect_equal(ds.class("sorted_df", datasources = conns)[[1]], "data.frame")
  })
  ```

  This was validated end to end, for real: `ensure_dslite_setup_file()`
  generates this exact code, `testthat::test_file()` auto-sources it as
  `setup.R`, a genuinely correct test passes against a real DSLite server,
  and a deliberately wrong test fails with a real error message — and only
  the passing one survives in the committed file.

  DSLite ships its own **built-in canned datasets** — no external server,
  no credentials, nothing package-specific to configure:
  `setupCNSIMTest()`, `setupDASIMTest()`, `setupDATASETTest()`,
  `setupDISCORDANTTest()`, `setupSURVIVALTest()`. Each wraps
  `setupDSLiteServer()` with one of DSLite's bundled 3-study simulated
  datasets. Documented in `config/dslite-canned-datasets.json`, with real
  shapes/columns confirmed by actually loading them:
  - **CNSIM** (2163 rows/study): health-style numeric/binary columns
    (LAB_TSC, LAB_TRIG, LAB_HDL, PM_BMI_CONTINUOUS, DIS_CVA, DIS_DIAB...) —
    the sensible general-purpose default.
  - **DASIM** (10000 rows/study): same shape as CNSIM, larger sample.
  - **DATASET** (71 rows/study): purpose-built for type/edge-case coverage
    (CHARACTER, LOGICAL, NA_VALUES, NULL_VALUES, INTEGER...).
  - **DISCORDANT** (12 rows/study): tiny 2-column (A, B) for
    concordance/discordance-style comparisons.
  - **SURVIVAL** (2060 rows/study): time-to-event columns for
    survival-analysis functions.

  Claude picks which one fits (`dslite_dataset` field in the `submit_tests`
  tool call, enum derived from this same config so it can't drift from what
  it was actually offered in the prompt).

- **Florian already has prior art here**: his own package `DSFunctionCreator`
  has an `init.dsTest()` function that scaffolds a DSLite-based `testthat`
  setup (a `setup.R` defining the DSLite server, a customized
  `testthat.R`).

### setup.R interaction — locked in

**Detect and reuse if present; generate minimal scaffolding only if
absent.** Check `tests/testthat/setup.R` first. If it already defines a
DSLite login/connection setup (e.g. via `DSFunctionCreator`'s
`init.dsTest()` or hand-written), generated tests assume and build on that
existing setup — never duplicate or second-guess it. Only construct fresh
DSLite scaffolding from scratch when no `setup.R` exists at all.

### Dataset selection — locked in, simplified after real validation

Originally designed around a "caller domain mismatch" concern (a
centrally-chosen dataset could be wrong for a third-party caller's actual
domain) and a `datashield-example-env.json`-based matching mechanism to
guard against it. **That concern turned out to not really apply once
DSLite's real mechanism was understood**: `datashield-example-env.json`
describes how to connect to a real, remote Opal demo server (for roxygen's
*documentation* usage examples) — a completely different scenario from
DSLite, which is serverless/in-process and ships its own bundled datasets.
No caller needs credentials, network access, or a domain-matched config
entry for DSLite to work at all. That eliminated the entire "skip because
no domain match" fallback tier — it's simply not a real failure mode here.

**Priority order, now just two tiers:**

1. **Existing `tests/testthat/setup.R` with DSLite scaffolding already
   present** → use it as-is, no dataset suggestion at all. Still the
   "caller already has it integrated, don't second-guess it" case.
2. **No existing `setup.R`** → Claude picks one of DSLite's 5 built-in
   canned datasets (`config/dslite-canned-datasets.json`, see above) and a
   fresh `setup.R` is generated using it. This essentially always
   succeeds — no skip branch needed for this tier.

### What a runnable DSLite-based test actually needs — three pieces, one turned out automatic

1. **The right test dataset(s)** — resolved via the priority order above.
2. **The server-side package installed in CI** (`dsBase`, `dsTidyverse`,
   whatever pairs with the client package under test) — still needed, via
   `needs: check` in the workflow (not yet validated against a real CI run,
   only locally where the packages were already installed).
3. ~~Correct DSLite method registration (e.g.
   `dslite.server$assignMethod(...)`)~~ — **confirmed unnecessary by
   actually running it.** `setupCNSIMTest(packages = c("dsTidyverseClient"))`
   auto-discovered and registered `arrangeDS` with zero manual
   registration call. The "server function called" identification (reused
   from roxygen's `@details` field) is NOT load-bearing here after all —
   contrary to what this doc originally claimed.

## OPEN QUESTIONS — still not decided

- How exactly `R-CMD-Check.yml` should capture and hand off per-function
  coverage data to this new workflow (format, storage/passing mechanism
  between jobs) — not yet designed. `has_adequate_coverage()` uses a
  coarse presence-heuristic placeholder in the meantime (explicitly
  commented as such in the function itself).
- Whether/how the `changed`-mode PR trigger determines "which functions
  are new or modified" (likely a `git diff` against the PR base, same
  technique `roxygen-suggest.yml` already uses) — needs confirming this
  reuses that exact mechanism or needs adjustment for test-file mapping.
- Whether `needs: check` in the workflow yml actually makes the target
  package's own functions resolvable to `testthat::test_file()` in a real
  CI run — validated locally (where the package was manually pre-loaded
  into the session), not yet validated in an actual GitHub Actions run
  where the package must be built/installed/loaded from scratch.

## REFACTORING DONE (beyond the DSLite correction above)

- **`call_claude_tool()`** (`R/functions/call_claude_tool.R`) — extracted
  shared low-level Claude request/error-handling/tool-extraction logic,
  previously duplicated verbatim across roxygen's `ask_claude()`,
  `ask_claude_for_tests()`, and `ask_claude_to_classify_failure()`. All
  three now just build their own prompt + tool schema and call this.
- **`post_github_json()`** (`R/functions/post_github_json.R`) — same idea
  for the GitHub API POST boilerplate, shared across
  `post_test_failure_comment()`, `create_bug_issue()`, and (retroactively)
  roxygen's own posting logic.
- **Removed `R/functions/post_suggestion_comment.R`** — dead code. It
  posted PR *suggestion* comments, but `roxygen-suggest.yml` was already
  updated (before this session) to commit directly to the PR branch
  instead; nothing called this function anymore. Found by grepping for
  its own name across the repo, not assumed.
- **Removed `R/functions/resolve_dslite_dataset.R`** — superseded
  entirely by the simplified two-tier dataset selection above; its
  `datashield-example-env.json`-matching logic no longer applies.
