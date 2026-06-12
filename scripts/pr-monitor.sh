#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '[pr-review-service] %s\n' "$*"; }
warn() { printf '[pr-review-service][WARN] %s\n' "$*" >&2; }

enabled="${PR_MONITOR_ENABLED:-false}"
repository="${PR_MONITOR_REPOSITORY:-Tracker-Dashboard/tracker-dashboard}"
interval="${PR_MONITOR_INTERVAL_SECONDS:-300}"
run_timeout="${PR_MONITOR_TIMEOUT_SECONDS:-2700}"
max_retries="${PR_MONITOR_MAX_RETRIES:-3}"
state_dir="${PR_MONITOR_STATE_DIR:-/var/lib/pr-monitor}"
checkout_dir="${PR_MONITOR_CHECKOUT_DIR:-/workspace/CodingOnline/.maintenance/tracker-dashboard}"
context_file="${PR_MONITOR_CONTEXT_FILE:-/workspace/private-context/tracker-dashboard/TRACKER_DASHBOARD_CONTEXT.md}"
git_name="${PR_MONITOR_GIT_NAME:-Aerya}"
git_email="${PR_MONITOR_GIT_EMAIL:-Aerya@users.noreply.github.com}"

if [ "$enabled" != "true" ]; then
  log 'disabled; set PR_MONITOR_ENABLED=true to start continuous review'
  exec sleep infinity
fi

if [ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
  warn 'GITHUB_PERSONAL_ACCESS_TOKEN is required'
  exit 1
fi

if ! command -v codex >/dev/null 2>&1 || ! command -v gh >/dev/null 2>&1; then
  warn 'codex and gh must both be installed'
  exit 1
fi

export GH_TOKEN="$GITHUB_PERSONAL_ACCESS_TOKEN"
mkdir -p "$state_dir" "$(dirname "$checkout_dir")"
find "$state_dir" -maxdepth 1 -type d -name 'lock-*' -exec rmdir {} + 2>/dev/null || true

if ! codex login status 2>&1 | grep -q 'Logged in using ChatGPT'; then
  warn 'Codex is not authenticated with ChatGPT in the shared /root/.codex volume'
  exit 1
fi

gh auth setup-git >/dev/null
git config --global user.name "$git_name"
git config --global user.email "$git_email"

if [ ! -d "$checkout_dir/.git" ]; then
  log "cloning $repository"
  gh repo clone "$repository" "$checkout_dir" -- --filter=blob:none
fi

check_state() {
  local sha="$1"
  gh api "repos/$repository/commits/$sha/check-runs" --jq '
    [.check_runs[]
      | select(.name == "Node build" or .name == "Docker build and CVE scan")
      | .conclusion]
    | if any(. == "failure" or . == "cancelled" or . == "timed_out" or . == "action_required")
      then "failure"
      elif length == 0 then "initial"
      elif all(. == "success" or . == "skipped" or . == "neutral") then "success"
      else "pending"
      end'
}

review_pr() (
  local number="$1"
  local expected_sha="$2"
  local trigger="$3"
  local lock_dir="$state_dir/lock-$number"
  local marker="$state_dir/pr-$number-$expected_sha-$trigger.done"
  local retry_file="$state_dir/pr-$number-$expected_sha-$trigger.retries"

  [ -e "$marker" ] && return 0
  local retries=0
  if [ -s "$retry_file" ]; then
    retries="$(cat "$retry_file")"
  fi
  if [ "$retries" -ge "$max_retries" ]; then
    return 0
  fi
  if ! mkdir "$lock_dir" 2>/dev/null; then
    log "PR #$number is already being handled"
    return 0
  fi

  cleanup_lock() { rmdir "$lock_dir" 2>/dev/null || true; }
  trap cleanup_lock EXIT

  local current_sha
  current_sha="$(gh pr view "$number" --repo "$repository" --json headRefOid --jq .headRefOid)"
  if [ "$current_sha" != "$expected_sha" ]; then
    log "PR #$number moved before review; deferring"
    return 0
  fi

  log "reviewing PR #$number at ${expected_sha:0:7} ($trigger)"
  git -C "$checkout_dir" reset --hard >/dev/null
  git -C "$checkout_dir" clean -fd >/dev/null
  git -C "$checkout_dir" fetch --prune origin >/dev/null
  git -C "$checkout_dir" switch --detach "$expected_sha" >/dev/null

  local prompt_file="$state_dir/prompt-$number.txt"
  cat > "$prompt_file" <<EOF
Maintain $repository and handle pull request #$number autonomously.

This is an internal, non-draft pull request. Aerya explicitly authorizes you to:
- inspect the complete diff, discussion, checks and workflow logs;
- correct concrete defects directly on the existing PR branch;
- commit with neutral functional wording and push the correction;
- approve the PR and enable protected squash auto-merge after verification.

Read $context_file when it exists and follow repository instructions. Before any
push, fetch again and confirm the remote head is still $expected_sha or the SHA
created by your own work. Never force-push, bypass checks, weaken protection,
expose secrets, run on a fork, or publish files/comments/branch names identifying
the tool used. Preserve contributor intent and unrelated work.

Run the repository-prescribed build, integration checks and focused tests. Do not
merge with administrator privileges. Let required checks and normal auto-merge be
the final gate. If intent is genuinely ambiguous or unsafe, leave a concise,
neutral blocking review and stop instead of guessing. Do not ask for interactive
input: finish the safe work possible in this run.
EOF

  local log_file="$state_dir/pr-$number-$(date -u +%Y%m%dT%H%M%SZ).log"
  set +e
  (
    cd "$checkout_dir"
    timeout "$run_timeout" codex -c model_reasoning_effort=high exec \
      --sandbox danger-full-access \
      --ephemeral \
      "$(cat "$prompt_file")"
  ) >"$log_file" 2>&1
  local status=$?
  set -e

  rm -f "$prompt_file"
  if [ "$status" -ne 0 ]; then
    retries=$((retries + 1))
    printf '%s\n' "$retries" > "$retry_file"
    warn "PR #$number review exited with status $status; see $log_file"
    return 0
  fi

  rm -f "$retry_file"
  touch "$marker"
  local final_sha
  final_sha="$(gh pr view "$number" --repo "$repository" --json headRefOid --jq .headRefOid 2>/dev/null || true)"
  if [ -n "$final_sha" ]; then
    touch "$state_dir/pr-$number-$final_sha-initial.done"
  fi
  log "PR #$number review completed"
)

while true; do
  while IFS=$'\t' read -r number sha; do
    [ -n "$number" ] || continue
    state="$(check_state "$sha" 2>/dev/null || printf 'initial')"
    if [ ! -e "$state_dir/pr-$number-$sha-initial.done" ]; then
      review_pr "$number" "$sha" initial
    elif [ "$state" = 'failure' ]; then
      review_pr "$number" "$sha" failure
    fi
  done < <(
    gh api --paginate "repos/$repository/pulls?state=open&per_page=100" --jq '
      .[]
      | select(.draft == false)
      | select(.head.repo.full_name == .base.repo.full_name)
      | [.number, .head.sha]
      | @tsv' 2>/dev/null || true
  )

  sleep "$interval"
done
