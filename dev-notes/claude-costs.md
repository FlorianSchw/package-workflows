# Claude costs

Cost pass of 2026-10-05 (user's request: "how can time spent with Claude be
minimised"). Prices and measured expectations from the Pricing and "Optimizing
for cost and intelligence" pages, both fetched 2026-10-05.

## Scope and profile

All calls go through `call_claude_tool()` (raw HTTP from R, first-party
Claude API, forced tool call):

| Call | Model, settings | Per call (Console logs, 2026-09-26) |
|---|---|---|
| Test review (`test-review`) | Opus 5, adaptive thinking, effort high | ~4–8k input, ~1.2–1.9k output; much more input with large setup files (dsBaseClient's support files ≈ 60k characters) |
| Failure classification | Opus 5, adaptive thinking, effort high | ~1.9k input, ~170 output |
| Roxygen review | Sonnet 5, thinking off | ~3.6–10k input, ~1.1–2.8k output |
| Analysis scripts | Opus 5, adaptive thinking | rare; one call plus a repair round per plan change |

Rates (2026-10-05, per million tokens): Opus 5 $5 input / $25 output, 5-minute
cache write $6.25, cache read $0.50 (0.1×); Sonnet 5 $2 / $10. Output dominates
per call (half to two thirds of the cost); in test runs with large support
files, the repeated input is the other large item.

**No eval exists** for the bot's output — quality is judged by the user on the
suggestion PRs. So only free wins (no change in what the model is asked to do)
were applied; trade-offs stay proposals.

## Applied (free wins)

1. **Usage logged per call** (`log_claude_usage()`): input, cache write,
   cache read, output and thinking tokens in the job log. The measurement
   channel for everything below — there is no Admin API key.
2. **Prompt caching for the test review.** The prompt is split at
   `<!-- per function -->` (`split_cached_prompt()`): instructions, the
   package's setup/helper files (and what they source) and the test-data
   structure first, with a cache marker; the function, its tests, results,
   history and earlier findings after it. The tool definition renders
   before the prompt, so it is now **the same for every function of a run**
   — the per-function enums (test file names, earlier finding ids, offered
   DSLite datasets) were removed from `build_submit_tests_tool()`; R
   already checks every returned value (`sort_test_decisions()`,
   `handle_failed_new_test()`, and `merge_test_findings()`, which now also
   ignores ids of other functions' findings). Checked in a sandbox: tool and
   shared part byte-identical across the three functions of a run.
   Expected: from the second function of a run, the shared part bills at
   0.1× (5-minute TTL; `cache_ttl: 1h` in a profile switches the TTL — only
   worth it if calls of a run start more than 5 minutes apart). Pays in
   sweeps and multi-file PRs only: **the cache never carries over between
   runs** (hours or days apart — the user's case; neither TTL nor a
   keep-alive pays there). So the prompt is split **only when the run
   reviews more than one file** (`cache_prompt` in `suggest_tests.R`,
   user's decision 2026-10-05); a single-file run sends it in one piece and
   costs what it did before, instead of paying the 1.25× write for nothing
   (a fraction of a cent to ~2 cents at Opus 5 prices, versus ~2–7 cents
   saved per further function, for shared parts of ~4k–15k tokens).
   **Verify** in the first real multi-function run: "cache read" > 0 from
   the second "Claude usage (submit_tests …)" line on.
3. **Roxygen returns only the fields it changes.** The documentation fields
   are optional in `build_submit_review_tool()`, the prompt asks to leave
   unchanged fields out, and `build_roxygen_block()` keeps the original
   lines for them (as it already did for not-accepted ones). A change listed
   without text is dropped (`accepted_roxygen_fields()`), so nothing is
   emptied. Cuts output — the expensive part — for files where few fields
   change. Roxygen can't use caching: its tool schema lists each function's
   parameters.

## Skipped

- **Batch API (50 %)** — the test review is a multi-step loop per function
  (run tests → Claude → run candidates → classify), which a single-shot
  batch request can't do; only the roxygen sweep would fit, and it runs on
  the cheapest model. Revisit if sweep costs show up on the Cost page.
- **Caching for roxygen** — per-function tool schema (above).

## Proposed trade-offs (need a before/after on real cases)

- **Opus 5.5 instead of Opus 5** for tests and analysis: cheaper per token
  ($4 / $20, cache reads 0.05×) and the pages' recommended starting model.
  Not a drop-in: forced `tool_choice` returns a 400 on Opus 5.5 (use `auto`
  + `strict: true` + a prompt instruction), thinking can't be disabled, and
  its default effort is `medium`. A migration, to be compared on a few real
  PRs.
- **Effort `medium` for the test review**: on long-horizon coding the pages
  report ~2.5 points lower accuracy for ~70 % of the cost; on knowledge work
  `medium` matched `high`.
- **Sonnet for the failure classification**: a small, checkable task.

## Next

Read the "Claude usage" lines of the next real runs (dsSupportClient,
dsSurvivalClient): cache hits from the second test function on, and roxygen
output per file compared with the ~1.1–2.8k before.
