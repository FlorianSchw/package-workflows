#!/usr/bin/env bash
# Decides whether a suggestion run does anything, its mode and its branch,
# from the event alone (GITHUB_EVENT_NAME, the event JSON at
# GITHUB_EVENT_PATH, GITHUB_REF, HEAD_REF, REF_NAME, ACTOR) and the inputs
# (SCAN_MODE, SWEEP_BASE, ALLOW_SWEEP). Writes skip, mode, ref and branch
# to GITHUB_OUTPUT. Called by action.yml.
set -eo pipefail

out() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }
skip() {
  echo "::notice::Nothing to do: $1"
  out skip true
  exit 0
}

event="$GITHUB_EVENT_NAME"
branch="${HEAD_REF:-$REF_NAME}"
field() { jq -r "$1 // empty" "$GITHUB_EVENT_PATH"; }

# --- Runs that should do nothing ---------------------------------------------

case "$branch" in bot-suggest/*) skip "this is the bot's own branch ($branch)." ;; esac
if [ "$event" = "push" ]; then
  case "$GITHUB_REF" in refs/tags/*) skip "a tag was pushed ($GITHUB_REF)." ;; esac
  [ "$(field '.deleted')" = "true" ] && skip "the branch $branch was deleted."
fi
if [ "$event" = "pull_request" ]; then
  head_repo="$(field '.pull_request.head.repo.full_name')"
  [ -n "$head_repo" ] && [ "$head_repo" != "$GITHUB_REPOSITORY" ] && \
    skip "the pull request comes from a fork ($head_repo), which gets no secrets and can't receive the bot's commits."
fi
[ "$ACTOR" = "dependabot[bot]" ] && skip "Dependabot runs get no secrets."

# --- Mode ------------------------------------------------------------------------

mode="$SCAN_MODE"
if [ "$mode" = "auto" ]; then
  case "$event" in
    pull_request|push) mode="changed" ;;
    *) mode="all" ;;
  esac
fi
case "$mode" in
  changed)
    case "$event" in
      pull_request|push) ;;
      *) skip "scan-mode \"changed\" needs a pull request or a push, this run was started by $event." ;;
    esac
    out skip false
    out mode changed
    out ref "$branch"
    out branch "$branch"
    ;;
  all)
    [ "$ALLOW_SWEEP" = "true" ] || skip "this workflow has no sweep; it runs on pull requests and pushes."
    base="$SWEEP_BASE"
    if [ -z "$base" ]; then
      # A schedule always starts on the default branch, so it sweeps dev;
      # a manual run sweeps the branch chosen in "Run workflow".
      if [ "$event" = "workflow_dispatch" ]; then base="$REF_NAME"; else base="dev"; fi
    fi
    echo "Sweep of $base."
    out skip false
    out mode all
    out ref "$base"
    out branch "$base"
    ;;
  *) echo "::error::Unknown scan-mode \"$SCAN_MODE\" (auto, changed or all)."; exit 1 ;;
esac
