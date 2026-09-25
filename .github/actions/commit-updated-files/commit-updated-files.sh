#!/usr/bin/env bash
# Commits exactly the files listed in $MANIFEST and proposes them as a PR.
# Called by action.yml, which sets all variables used here from the inputs.
#   "changed": per-file commits on a sub-branch, PR back into the current
#              branch, plus a link comment on the originating PR.
#   "all":     one commit on this month's sweep branch, PR against the
#              sweep base.
# Does nothing if the manifest is empty or nothing actually changed.
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

# Writes the PR body — text $1 plus the pr-body-file report, if any — to a
# temporary file and prints its path.
write_body() {
  local file
  file="$(mktemp)"
  printf '%s\n' "$1" > "$file"
  if has_content "$PR_BODY_FILE"; then
    printf '\n' >> "$file"
    cat "$PR_BODY_FILE" >> "$file"
  fi
  echo "$file"
}

# Proposes branch $1 as a PR into $2 with title $3 and body text $4. Opens a
# new PR and prints its URL; if one is already open, refreshes its body when
# there is a report — without one, the body is left alone in case someone
# edited it — and prints nothing.
propose() {
  local branch="$1" base="$2" title="$3" body_file existing
  body_file="$(write_body "$4")"
  existing="$(open_pr "$branch")"
  if [ -z "$existing" ]; then
    gh pr create --base "$base" --head "$branch" --title "$title" --body-file "$body_file"
  elif has_content "$PR_BODY_FILE"; then
    gh pr edit "$existing" --body-file "$body_file" > /dev/null
  fi
}

if ! has_content "$MANIFEST"; then
  echo "No updated files — nothing to commit."
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

# --- "all": one commit on this month's sweep branch ----------------------------

if [ "$SCAN_MODE" = "all" ]; then
  while IFS= read -r f; do git add -- "$f"; done < "$MANIFEST"
  if git diff --cached --quiet; then
    echo "Manifest files have no actual changes — skipping sweep PR."
    exit 0
  fi

  branch="${SWEEP_BRANCH_PREFIX}-$(date +%Y-%m)"
  git checkout -b "$branch"
  git commit -m "$SWEEP_COMMIT_MESSAGE"
  git_push_with_token --force origin "$branch"  # a re-run in the same month replaces it
  propose "$branch" "$SWEEP_BASE" "$SWEEP_PR_TITLE" "$SWEEP_PR_BODY" > /dev/null
  exit 0
fi

# --- "changed": per-file commits on a sub-branch of the current branch ---------

original="$(git rev-parse --abbrev-ref HEAD)"
if [ "$original" = "HEAD" ]; then
  echo "::error::Detached HEAD — expected a named branch to be checked out. Aborting."
  exit 1
fi
sub_branch="${SUB_BRANCH_PREFIX}/${original//\//-}"
git checkout -b "$sub_branch"

committed=""  # Markdown list of committed files, for the link comment
while IFS= read -r f; do
  git add -- "$f"
  if git diff --cached --quiet -- "$f"; then
    echo "No actual change for $f — skipping commit."
    continue
  fi
  git commit -m "$COMMIT_PREFIX $f"
  committed+="- \`$f\`"$'\n'
done < "$MANIFEST"

if [ -z "$committed" ]; then
  echo "No files actually changed — skipping sub-branch push."
  exit 0
fi

git_push_with_token --force origin "$sub_branch"
pr_url="$(propose "$sub_branch" "$original" "$SUB_PR_TITLE" "$SUB_PR_BODY")"

# Link comment on the originating PR — only when a sub-PR was newly opened.
if [ -n "$pr_url" ] && [ -n "$ORIGIN_PR_NUMBER" ]; then
  comment="**${SUB_PR_TITLE}** opened: ${pr_url} (into \`${original}\`)"
  if has_content "$COMMENT_SUMMARY_FILE"; then
    comment+=$'\n\n'"$(cat "$COMMENT_SUMMARY_FILE")"
  fi
  comment+=$'\n\n'"$committed"
  gh pr comment "$ORIGIN_PR_NUMBER" --body "$comment" \
    || echo "::warning::Failed to post notification comment on PR #$ORIGIN_PR_NUMBER"
fi
