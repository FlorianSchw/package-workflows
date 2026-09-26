#!/usr/bin/env bash
# Commits the files listed in $FILES (one per line) to $BRANCH in one
# commit with $COMMIT_MESSAGE and pushes it. Called by action.yml, which
# sets all variables used here from the inputs. Does nothing if none of the
# files actually changed. If the push is rejected because the branch moved
# on (e.g. two merges in quick succession), rebases onto it and tries
# again, up to three times. A rejection for any other reason (a rule, a
# missing permission) stops at once — retrying can't fix it.
set -eo pipefail

# actions/checkout stores GITHUB_TOKEN as an extra HTTP header
# (persist-credentials), which wins over the token in the remote URL — our
# pushes would go out as github-actions, and GitHub doesn't run (or asks
# approval for) workflows on events from GITHUB_TOKEN. An empty value resets
# that header, so the given token is used. Same as commit-updated-files.
git_with_token() { git -c "http.https://github.com/.extraheader=" "$@"; }

if [ -z "$BRANCH" ]; then
  echo "::error::No branch to push to. Aborting."
  exit 1
fi

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

while IFS= read -r f; do
  [ -n "$f" ] && git add -- "$f"
done <<< "$FILES"

if git diff --cached --quiet; then
  echo "No actual changes — nothing to commit."
  exit 0
fi

git commit -m "$COMMIT_MESSAGE"

for attempt in 1 2 3; do
  if git_with_token push origin "HEAD:refs/heads/$BRANCH"; then
    exit 0
  fi
  before="$(git rev-parse HEAD)"
  git_with_token pull --rebase origin "$BRANCH"
  if [ "$(git rev-parse HEAD)" = "$before" ]; then
    echo "::error::Push to $BRANCH was rejected, but $BRANCH hasn't moved on — see the reason above (e.g. a branch rule or a missing permission)."
    exit 1
  fi
  echo "Push rejected (attempt $attempt) because $BRANCH moved on — rebased, trying again."
done

echo "::error::Could not push to $BRANCH after 3 attempts."
exit 1
