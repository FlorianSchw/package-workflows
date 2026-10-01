#!/usr/bin/env bash
# Works out what is new since the last suggestion run on a branch, after
# checkout (fetch-depth: 0). Design: dev-notes/suggestions-trigger-model.md.
#
# Starting point, first match wins:
#   1. the marker "<!-- bot-suggest: reviewed up to <sha> -->" in the open
#      bot PR's description (catches up dropped or failed runs);
#   2. a PR that was opened or reopened: the PR's base (the whole PR);
#   3. the event's "before" (push, PR synchronize);
#   4. none (a new branch): commits that exist on no other branch.
# Push and synchronize runs count only commits on no other branch, so
# commits merged in from dev aren't reviewed or credited. Merge commits
# and the bot's own commits (author or subject, from bot-authors.json) are
# left out. If the history was rewritten (the starting point is no
# ancestor of HEAD), rebuild=true: the bot branch can't be built on.
#
# Env: BRANCH, SUB_BRANCH (the bot branch for BRANCH), FILE_PATTERN
# (pathspec like 'R/*.R'; empty: commits only), BOT_CONFIG (path to
# bot-authors.json), GH_TOKEN, plus GITHUB_EVENT_NAME, GITHUB_EVENT_PATH.
# Writes commits.txt (one sha per line), files_to_check.txt (FILE_PATTERN
# matches still present at HEAD), and count, base_rev, rebuild,
# reviewed_sha to GITHUB_OUTPUT.
set -eo pipefail

out() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }
field() { jq -r "$1 // empty" "$GITHUB_EVENT_PATH"; }
exists() { git cat-file -e "$1^{commit}" 2>/dev/null; }
is_ancestor() { git merge-base --is-ancestor "$1" HEAD 2>/dev/null; }
zeros="0000000000000000000000000000000000000000"

head="$(git rev-parse HEAD)"
event="$GITHUB_EVENT_NAME"
action="$(field '.action')"
rebuild=false
start=""
range_is_pr=false

# 1. Marker in the open bot PR
body="$(gh pr list --head "$SUB_BRANCH" --state open --json body --jq '.[0].body // empty' 2>/dev/null || true)"
# (No marker is the normal case for a first run: grep finding nothing must not end the script.)
marker="$(printf '%s' "$body" | { grep -oE 'bot-suggest: reviewed up to [0-9a-f]{7,40}' || true; } | tail -1 | awk '{print $NF}')"
if [ -n "$marker" ]; then
  if exists "$marker" && is_ancestor "$marker"; then
    start="$marker"
    echo "Continuing from the open bot PR's marker ($marker)."
  else
    echo "The marker $marker isn't in this branch's history any more (rewritten); rebuilding the bot branch."
    rebuild=true
  fi
fi

# 2./3. The event
if [ -z "$start" ]; then
  if [ "$event" = "pull_request" ] && { [ "$action" = "opened" ] || [ "$action" = "reopened" ] || [ -z "$(field '.before')" ]; }; then
    base_ref="$(field '.pull_request.base.ref')"
    start="$(git merge-base "origin/$base_ref" HEAD)"
    range_is_pr=true
    echo "Whole pull request (base $base_ref)."
  else
    before="$(field '.before')"
    if [ -n "$before" ] && [ "$before" != "$zeros" ] && exists "$before"; then
      start="$before"
      is_ancestor "$before" || { echo "History rewritten since $before (force-push)."; rebuild=true; }
      echo "Changes since $before."
    else
      echo "New branch: commits that exist on no other branch."
    fi
  fi
fi

# --- Commits ------------------------------------------------------------------------

others=()
if [ "$range_is_pr" = false ]; then
  while IFS= read -r ref; do
    case "$ref" in
      refs/remotes/origin/HEAD|"refs/remotes/origin/$BRANCH"|refs/remotes/origin/bot-suggest/*) ;;
      *) others+=("$ref") ;;
    esac
  done < <(git for-each-ref --format='%(refname)' refs/remotes/origin)
fi

if [ -n "$start" ]; then range=("$start..HEAD"); else range=("HEAD"); fi
git rev-list --no-merges "${range[@]}" ${others[@]:+--not "${others[@]}"} > all_commits.txt

bot_names="$(jq -r '.bot_names[]? // empty' "$BOT_CONFIG")"
bot_subjects="$(jq -r '.bot_commit_subjects[]? // empty' "$BOT_CONFIG")"
: > commits.txt
while IFS= read -r c; do
  [ -z "$c" ] && continue
  author="$(git log -1 --format=%an "$c")"
  subject="$(git log -1 --format=%s "$c")"
  if printf '%s\n' "$bot_names" | grep -qxF -- "$author"; then continue; fi
  bot_subject=false
  while IFS= read -r prefix; do
    [ -n "$prefix" ] && case "$subject" in "$prefix"*) bot_subject=true ;; esac
  done <<< "$bot_subjects"
  [ "$bot_subject" = true ] && continue
  echo "$c" >> commits.txt
done < all_commits.txt
rm -f all_commits.txt

# --- Files ----------------------------------------------------------------------------

: > files_to_check.txt
if [ -n "$FILE_PATTERN" ]; then
  while IFS= read -r c; do
    git diff-tree --no-commit-id --name-only -r "$c" -- "$FILE_PATTERN"
  done < commits.txt | sort -u | while IFS= read -r f; do
    [ -f "$f" ] && echo "$f"
  done > files_to_check.txt
  count="$(wc -l < files_to_check.txt | tr -d ' ')"
else
  count="$(wc -l < commits.txt | tr -d ' ')"
fi

# Base for the test workflow's history evidence: the starting point, or for
# a new branch the parent of its oldest new commit.
base_rev="$start"
if [ -z "$base_rev" ] && [ -s commits.txt ]; then
  base_rev="$(git rev-parse "$(tail -1 commits.txt)^" 2>/dev/null || true)"
fi

echo "$(wc -l < commits.txt | tr -d ' ') new commit(s), $( [ -n "$FILE_PATTERN" ] && echo "$count file(s) to check" || echo "no file filter" )."
out count "$count"
out base_rev "$base_rev"
out rebuild "$rebuild"
out reviewed_sha "$head"
