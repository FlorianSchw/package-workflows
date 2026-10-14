# Review of the Claude-assisted workflows (2026-10-14)

User's request: are roxygen, tests, analysis and naming structured well;
should parts of what Claude does move to R (with Claude called again
where needed) to save tokens; what should be refactored.

## Verdict

The basic split holds everywhere: Claude returns small, validated fields;
R assembles, checks and runs. The savings are mostly in **when Claude is
called** and in **context sent again unchanged**, not in what one call
does.

| Workflow | Claude does | R does | Verdict |
|---|---|---|---|
| Roxygen (Sonnet 5, per function) | Check docs against code, write changed fields, possible bugs | Build block, reason filter, declined changes | Right split; called for every listed file, also when nothing relevant changed |
| Tests (Opus 5, high effort) | Judge existing tests, write new ones, failure verdicts | Run tests, place, keep passing, DSLite, report | Right split; no R signals to skip or focus; one Opus call per failed test |
| Analysis (Opus 5) | Scripts per plan step, repair rounds | Mock data, installs, call checks, test run | Structured steps (`model:`) could be built in R; repair rounds were uncached (done, see below) |
| Naming (Sonnet 5) | Only arguments the code can't place | Everything else | Already R-first |

## Token levers, by impact

1. **Review only what changed since the last review** (sweeps and
   manual runs). User's view (2026-10-14): a manual run
   (`workflow_dispatch`) should check diffs, not unchanged files; the
   lookback/rotation sweep is not well thought through. **No hidden git
   ref** for the memory (user's decision). Open: where "last reviewed"
   comes from — proposal below.
2. **Failure classification per function, not per failed test**; failures
   R can recognise (parse error, call to a function that exists nowhere)
   are `bad_test` without Claude.
3. ~~Analysis repair rounds uncached~~ Done 2026-10-14 with the
   step-by-step drafting (prompt split at `<!-- per request -->`,
   constant tool schema).
4. **Structured analysis steps in R** (`model:` with outcome, exposure,
   adjust, pooling → `ds.glm` / `ds.glmSLMA` from a template); Claude
   only for free-text steps. Fits stage 2.
5. Optional: **coverage for the test review** (`covr`: uncovered lines as
   input; skip when fully covered, all pass, no open findings).

Not worth it: roxygen prompt caching (per-function schema; cents at
Sonnet prices), batching naming calls, moving roxygen's "missing field"
detection to R.

## Proposal for 1: last review from the run history (no storage)

The last successful run of the same caller workflow on the same branch
(`gh api …/actions/workflows/<caller file>/runs?branch=…&status=success`,
caller file from `GITHUB_WORKFLOW_REF`) gives the commit it reviewed
(`head_sha`): take the newest one that is an ancestor of HEAD. Files
whose Claude call failed in that run are its "Suggestion not made"
warning annotations (check-run annotations API), reviewed again. No ref,
no commit, no cache. Manual run: diff since then, input `scope: changed
| all`; no earlier run: nothing (or `all`). Replaces
`sweep-lookback-days` / `sweep-rotation-months` and the inline selection
in `test-suggest.yml`; one selection for roxygen and tests. **Built
2026-10-14** (user's OK), with one change: a schedule starts on `main`
while reviewing `dev`, so each review records what it covered as a notice
annotation instead of relying on the run's commit. Details in
[suggestions-trigger-model.md](suggestions-trigger-model.md).

## Structure and refactoring

1. **`strict: true` for all tool calls**, also forced ones (works on
   Opus 5 / Sonnet 5); removes the analysis bot's "array as JSON string"
   workaround. Today only with `tool_choice_type: auto`.
2. **Hidden globals:** `api_key`, `anthropic_config`, prompt templates,
   `failure_classification_config` are read from the global environment
   by five functions. Pass one `claude` object (config + key) instead.
3. **Two R-file parsers:** `parse_r_file()` (regex, first function;
   roxygen, tests) and `read_r_definitions()` (R's parser, all
   functions; naming). Merge on the parser-based one in `shared/`.
4. **Main loops as functions:** the test loop (~160 lines) and the
   roxygen loop body become one function per R file; the shared
   skeleton (bot PR state, checkboxes, bot branch, stats, report) a
   shared helper.
5. Smaller: three config-reading styles (policy-file item), three push
   actions (purposes differ, documented).

## Order

1. Strict for all calls (after the Opus 5 baseline of the CI round, so
   the comparison stays clean).
2. Failure classification per function + R pre-check.
3. Review scope from the run history (after the user's OK).
4. Refactoring 2–4.
5. R templates for structured analysis steps (stage 2).
6. Coverage, only if needed.
