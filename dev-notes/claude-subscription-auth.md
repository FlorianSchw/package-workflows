# Claude Pro/Max subscriptions instead of WIF

Question (2026-10-14, user): can users run the Claude-assisted workflows on
their own Claude Pro/Max subscription instead of setting up Workload
Identity Federation?

**State: not pursued; nothing built.** Revisit only if users ask for it.

## Why it doesn't work as built

Every Claude call goes to the Messages API (`call_claude_tool()`, raw HTTP),
which is billed through a Console organization. A Pro/Max subscription
covers the Claude apps and Claude Code. Its CI token (`claude setup-token`,
used by `anthropics/claude-code-action`) is meant for Claude Code, not for
direct API calls, and as far as known Anthropic's terms don't allow using
subscription credentials that way. Check the current terms before building
anything on it.

## Options considered

1. **Plain API key as an alternative to WIF** (optional
   `anthropic-api-key` secret, used when the three WIF IDs are missing).
   Small change, but still Console billing and a long-lived secret.
   **Not wanted (user, 2026-10-14).**
2. **Run the Claude step through Claude Code** (`claude -p` or
   claude-code-action with the user's `CLAUDE_CODE_OAUTH_TOKEN`). The only
   route a subscription could pay for. Not now, because of the loss of
   control below, a second code path in every Claude-assisted workflow, and
   runs counting against the subscription's usage limits (a sweep can stop
   halfway).

## What "less control" means

R would no longer make one exact request per function with a structured
answer. It would hand a task to an agent that decides how to work on it.

- **Guaranteed structure:** today a forced tool call with our schema
  (enums for reasons, categories and confidence, item limits), enforced by
  the API; "Claude returns fields, R assembles the output" rests on that.
  Claude Code can be asked for JSON, newer versions take a schema, but the
  answer is checked after the agent's work. A violation means a retry or a
  lost function, not a guaranteed shape.
- **What Claude sees:** today R assembles the context exactly (function,
  tests, support files, earlier findings; e.g. `01_DS_Login.R` is never
  sent). Claude Code starts with its own system prompt, loads the
  repository's `CLAUDE.md`, can read any file in the checkout and, unless
  locked down, run commands. The checkout holds the caller's code,
  `.Renviron`-style files and token variables. It would need a strict list
  of allowed tools, no Bash and a cleaned environment; even then we only
  restrict what the agent does, we no longer decide it.
- **Per-task settings** (`config/claude.yml`): model per task, adaptive
  thinking with effort, `max_tokens`, server-side fallback, our cache
  breakpoint at `<!-- per function -->`, clean errors on `max_tokens` and
  `refusal`. Model and roughly effort remain settable; cache breakpoints and
  fallback don't. The models available depend on the user's plan.
- **Cost and runtime:** today one call per function (a few with the failure
  classification). An agent takes a varying number of turns (reading files,
  trying things), so tokens and runtime vary unless capped with a maximum
  number of turns; on a subscription that eats into limits the job can't see.
- **Measuring:** `log_claude_usage()` logs input, cache and output tokens
  per call, which the cost pass ([claude-costs.md](claude-costs.md)) and the
  cache check rely on. Claude Code reports per session; on a subscription
  the cost isn't visible at all.
- **Error handling:** our retry rules, token renewal and one warning
  annotation per failed function (job stays green) would become "the CLI
  exited non-zero", with Claude Code's own retries underneath.

**Conclusion:** for roxygen, tests and naming, where R builds the output
from small validated fields, the precision comes from the narrow, fully
controlled call. An agent run would give that up. Open-ended tasks such as
the analysis scripts would suit an agent better, if this is ever revisited.
