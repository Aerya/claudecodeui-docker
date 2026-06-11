# Continuous Repository Maintenance Policy

This policy applies equally to Codex and Claude Code. Its purpose is quiet,
consistent repository maintenance, not contributor surveillance.

## Operating model

- GitHub Actions and branch protection are the permanent 24/7 control plane.
- An agent run is an additional review and repair pass, not a replacement for CI.
- Only one agent may own a PR at a time. The second agent may review the result,
  but must not edit the same branch concurrently.
- Treat every contributor and every branch with the same rules.

## Default permissions

- Start read-only: inspect repository rules, PR metadata, diff, comments, checks,
  workflow logs, and the current branch head SHA.
- Never print or transmit credentials, tokens, cookies, private keys, or secrets.
- Never force-push, rewrite shared history, delete branches, disable checks,
  weaken branch protection, or use an administrator merge.
- Never execute code from an untrusted fork with repository secrets available.
- Never push to a fork or modify a fork PR branch.
- Do not merge merely because an AI review says `looks good`.

## Review sequence

1. Load the repository's `AGENTS.md`, `CLAUDE.md`, README, and workflow rules.
2. Fetch the latest remote state and confirm the PR base and head SHAs.
3. Read the entire diff and surrounding code before commenting.
4. Inspect all failed, skipped, and pending checks and their logs.
5. Check security, data integrity, API contracts, persistence, concurrency,
   frontend behavior, packaging, and rollback risk.
6. Run the repository-prescribed build, tests, lint, integration checks, and any
   focused reproduction needed for changed behavior.
7. Recheck the remote head SHA before posting a review or pushing a correction.

## Decision policy

- `PASS`: no blocking finding and all required checks pass. Auto-merge may remain
  enabled if repository policy already allows it.
- `FIX`: a narrow, proven correction is possible on an internal branch. Preserve
  contributor intent, add verification, and push only when repository/user policy
  authorizes agent corrections.
- `BLOCK`: security risk, data loss, unclear intent, failed required checks,
  untrusted fork, conflicting changes, or an unsafe permission request. Explain
  the blocker without merging.
- `WAIT`: checks are still running or another agent/contributor changed the head.
  Fetch again later; do not race them.

## Correction rules

- Keep diffs minimal and avoid unrelated cleanup.
- Never silently change product behavior to make a test pass.
- Add or improve a regression check when practical.
- Commit messages must describe the correction, not the contributor.
- After a push, let required checks rerun from the new SHA.
- Auto-merge is acceptable only through normal protected-branch rules.

## Review output

Report findings first, ordered by severity, with file and tight line references.
Explain impact and a concrete fix. If no issue is found, state that clearly and
name any remaining test gap. Avoid grading language or comments about a person's
skill level.

## Continuous-operation contract

The host scheduler may invoke an agent when a PR is opened, updated, marked ready,
or when a required check fails. It must also perform a low-frequency reconciliation
poll to recover missed events. Each invocation receives one repository and one PR.

The scheduler must enforce:

- one active lease per `owner/repository#pr`;
- a bounded runtime and retry count;
- no automatic work on draft PRs or forks;
- no repository-wide write token in an untrusted checkout;
- an audit log containing timestamps, PR/head SHA, checks run, decision, and any
  commits pushed, but never secret values;
- human notification for `BLOCK`, repeated failures, conflicts, or ambiguous intent;
- no endless agent-to-agent repair loop.

This file does not itself create a daemon. Keeping CloudCLI online only keeps the
interface available. Actual 24/7 behavior requires GitHub webhooks or a scheduler
that starts bounded agent runs, while branch protection remains the final gate.
