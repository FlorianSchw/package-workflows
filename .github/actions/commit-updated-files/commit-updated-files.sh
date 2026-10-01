#!/usr/bin/env bash
# Commits exactly the files listed in $MANIFEST and proposes them as a PR.
# Called by action.yml, which sets all variables used here from the inputs.
#   "changed": per-file commits on the bot branch of the current branch, PR
#              back into it, plus a link comment on the originating PR when
#              the bot PR is new. If a bot PR is already open, the bot
#              branch is built on (OPEN_SUGGESTION_PR=add): the current
#              branch is merged into it, the user's version winning, and
#              this run's suggestions are added; otherwise (none open,
#              "replace", REBUILD=true, or a merge that can't be resolved)
#              it is rebuilt from the current branch and force-pushed.
#              The bot PR's description carries the marker
#              "<!-- bot-suggest: reviewed up to <REVIEWED_SHA> -->", updated
#              on every run, also when there is nothing new to commit.
#              Design: dev-notes/suggestions-trigger-model.md.
#   "all":     one commit on this month's sweep branch of the sweep base,
#              PR against the sweep base.
# Does nothing if nothing actually changed (apart from the marker update).
set -eo pipefail

# True if $1 names a file with content.
has_content() { [ -n "$1" ] && [ -s "$1" ]; }

# actions/checkout stores GITHUB_TOKEN as an extra HTTP header
# (persist-credentials), which wins over the token in the remote URL — our
# pushes would go out as github-actions, and GitHub doesn't run (or asks
# approval for) workflows on events from GITHUB_TOKEN. An empty value resets
# that header, so the given token is used.
git_push_with_token() { git -c "http.https://github.com/.extraheader=" push "$@"; }

# Number of the open PR from branch $1, or nothing. Only an OPEN PR counts:
# branch names are reused (per source branch, per month), and an earlier
# merged or closed PR must not stop a new one.
open_pr() { gh pr list --head "$1" --state open --json number --jq '.[0].number // empty'; }

marker() { [ -n "$REVIEWED_SHA" ] && printf '<!-- bot-suggest: reviewed up to %s -->' "$REVIEWED_SHA"; }
strip_marker() { sed -E '/<!-- bot-suggest: reviewed up to [0-9a-f]+ -->/d'; }

# PR body for a new or rebuilt bot PR: text $1, the report, the marker.
write_body() {
  local file
  file="$(mktemp)"
  printf '%s\n' "$1" > "$file"
  if has_content "$PR_BODY_FILE"; then
    printf '\n' >> "$file"
    cat "$PR_BODY_FILE" >> "$file"
  fi
  marker >> "$file" || true
  echo "$file"
}

# PR body when building on open PR $1: its body without the old marker,
# this run's report appended as an update, the new marker. Kept below
# GitHub's 65536-character limit by dropping the oldest updates.
append_body() {
  local file update_heading
  file="$(mktemp)"
  gh pr view "$1" --json body --jq '.body' | strip_marker > "$file"
  if has_content "$PR_BODY_FILE"; then
    update_heading="### Update for ${REVIEWED_SHA:0:7}"
    printf '\n---\n%s\n\n' "$update_heading" >> "$file"
    cat "$PR_BODY_FILE" >> "$file"
  fi
  if [ "$(wc -c < "$file")" -gt 60000 ]; then
    # Keep the first part (intro and first report) and the newest update.
    awk -v max=30000 'length(acc) < max { acc = acc $0 "\n" } END { printf "%s", acc }' "$file" > "$file.head"
    { cat "$file.head"; printf '\n---\n_Earlier updates removed to stay within GitHub'"'"'s size limit._\n\n%s\n\n' "${update_heading:-}"; has_content "$PR_BODY_FILE" && cat "$PR_BODY_FILE"; } > "$file"
    rm -f "$file.head"
  fi
  printf '\n' >> "$file"
  marker >> "$file" || true
  echo "$file"
}

# Proposes branch $1 as a new PR into $2 with title $3 and body text $4, or
# refreshes the open one; prints the URL of a newly opened PR only.
propose() {
  local branch="$1" base="$2" title="$3" body_file existing
  existing="$(open_pr "$branch")"
  if [ -z "$existing" ]; then
    body_file="$(write_body "$4")"
    gh pr create --base "$base" --head "$branch" --title "$title" --body-file "$body_file"
  elif [ "$5" = "append" ]; then
    gh pr edit "$existing" --body-file "$(append_body "$existing")" > /dev/null
  elif has_content "$PR_BODY_FILE" || [ -n "$REVIEWED_SHA" ]; then
    gh pr edit "$existing" --body-file "$(write_body "$4")" > /dev/null
  fi
}

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

# --- "all": one commit on this month's sweep branch of the sweep base ------------

if [ "$SCAN_MODE" = "all" ]; then
  if ! has_content "$MANIFEST"; then
    echo "No updated files — nothing to commit."
    exit 0
  fi
  while IFS= read -r f; do git add -- "$f"; done < "$MANIFEST"
  if git diff --cached --quiet; then
    echo "Manifest files have no actual changes — skipping sweep PR."
    exit 0
  fi

  # The base is part of the name: sweeps of two bases in one month must not
  # share (and overwrite) a branch.
  branch="${SWEEP_BRANCH_PREFIX}-${SWEEP_BASE//\//-}-$(date +%Y-%m)"
  git checkout -b "$branch"
  git commit -m "$SWEEP_COMMIT_MESSAGE"
  git_push_with_token --force origin "$branch"  # a re-run in the same month replaces it
  REVIEWED_SHA="" propose "$branch" "$SWEEP_BASE" "$SWEEP_PR_TITLE" "$SWEEP_PR_BODY" > /dev/null
  exit 0
fi

# --- "changed": the bot branch of the current branch ----------------------------------

original="$(git rev-parse --abbrev-ref HEAD)"
if [ "$original" = "HEAD" ]; then
  echo "::error::Detached HEAD — expected a named branch to be checked out. Aborting."
  exit 1
fi
original_sha="$(git rev-parse HEAD)"
sub_branch="${SUB_BRANCH_PREFIX}/${original//\//-}"
existing="$(open_pr "$sub_branch")"

if ! has_content "$MANIFEST"; then
  if [ -n "$existing" ] && [ -n "$REVIEWED_SHA" ]; then
    gh pr edit "$existing" --body-file "$(append_body "$existing")" > /dev/null
    echo "No new suggestions; updated the marker of bot PR #$existing."
  else
    echo "No updated files — nothing to commit."
  fi
  exit 0
fi

# This run's files, set aside: the working tree may be switched to the bot
# branch below.
stash_dir="$(mktemp -d)"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  mkdir -p "$stash_dir/$(dirname "$f")"
  if [ -e "$f" ]; then cp -p "$f" "$stash_dir/$f"; else touch "$stash_dir/$f.deleted"; fi
done < "$MANIFEST"

mode="replace"
note=""
if [ -n "$existing" ] && [ "$OPEN_SUGGESTION_PR" = "add" ] && [ "$REBUILD" != "true" ]; then
  mode="add"
elif [ -n "$existing" ] && [ "$REBUILD" = "true" ]; then
  note="_The branch's history was rewritten (e.g. rebase), so this bot branch was rebuilt. Earlier suggestions that weren't merged are only in it again if their files were reviewed again._"
fi

if [ "$mode" = "add" ]; then
  # Undo this run's changes in the working tree (they are set aside), so
  # the bot branch can be checked out; other untracked files (reports,
  # .shared-workflows/) stay.
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if git ls-files --error-unmatch -- "$f" > /dev/null 2>&1; then git checkout --quiet HEAD -- "$f"; else rm -f -- "$f"; fi
  done < "$MANIFEST"
  git fetch --quiet origin "$sub_branch"
  git checkout --quiet -B "$sub_branch" "origin/$sub_branch"
  # Bring the user's new commits in; on conflicts their version wins.
  if ! git merge --quiet --no-edit -X theirs "$original_sha" -m "Merge branch '$original' into $sub_branch"; then
    git merge --abort || true
    echo "Merging $original into $sub_branch failed; rebuilding the bot branch instead."
    mode="replace"
    note="_Merging the new commits into this bot branch failed, so it was rebuilt with this run's suggestions only._"
  fi
fi
if [ "$mode" = "replace" ]; then
  git checkout --quiet -B "$sub_branch" "$original_sha"
fi

# This run's files on top.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [ -e "$stash_dir/$f.deleted" ]; then
    git rm --quiet --ignore-unmatch -- "$f"
  else
    mkdir -p "$(dirname "$f")"
    cp -p "$stash_dir/$f" "$f"
  fi
done < "$MANIFEST"
rm -rf "$stash_dir"

committed=""  # Markdown list of committed files, for the link comment
while IFS= read -r f; do
  [ -z "$f" ] && continue
  git add -A -- "$f"
  if git diff --cached --quiet -- "$f"; then
    echo "No actual change for $f — skipping commit."
    continue
  fi
  git commit --quiet -m "$COMMIT_PREFIX $f"
  committed+="- \`$f\`"$'\n'
done < "$MANIFEST"

if [ -n "$note" ] && has_content "$PR_BODY_FILE"; then printf '\n%s\n' "$note" >> "$PR_BODY_FILE"; fi

if [ -z "$committed" ] && [ "$mode" = "add" ]; then
  # Nothing new, but the merged-in commits and the marker are worth keeping.
  git_push_with_token origin "$sub_branch"
  gh pr edit "$existing" --body-file "$(append_body "$existing")" > /dev/null
  echo "No new suggestions; brought bot PR #$existing up to date."
  exit 0
fi
if [ -z "$committed" ]; then
  echo "No files actually changed — skipping the bot branch."
  exit 0
fi

if [ "$mode" = "add" ]; then
  git_push_with_token origin "$sub_branch"
  propose "$sub_branch" "$original" "$SUB_PR_TITLE" "$SUB_PR_BODY" append > /dev/null
  exit 0
fi

git_push_with_token --force origin "$sub_branch"
pr_url="$(propose "$sub_branch" "$original" "$SUB_PR_TITLE" "$SUB_PR_BODY")"

# Link comment on the originating PR — only when a bot PR was newly opened.
if [ -n "$pr_url" ] && [ -n "$ORIGIN_PR_NUMBER" ]; then
  comment="**${SUB_PR_TITLE}** opened: ${pr_url} (into \`${original}\`)"
  if has_content "$COMMENT_SUMMARY_FILE"; then
    comment+=$'\n\n'"$(cat "$COMMENT_SUMMARY_FILE")"
  fi
  comment+=$'\n\n'"$committed"
  gh pr comment "$ORIGIN_PR_NUMBER" --body "$comment" \
    || echo "::warning::Failed to post notification comment on PR #$ORIGIN_PR_NUMBER"
fi
