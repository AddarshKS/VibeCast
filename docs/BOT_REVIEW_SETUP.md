# Bot Review Setup

Checked September 16, 2026. This is a setup guide; no reviewer app, subscription, automatic fix agent, or repository rule was enabled by this change.

## Integration Background

Before the player-reliability integration, GitHub reported both PRs as merged, but their destinations differed:

- PR #1 merged into `main` at `198ca09`.
- PR #2 merged afterward into `codex/public-beta` at `0f8b468`, not into `main`.
- The PR #2 head `b181dcc` and `codex/public-beta` at `0f8b468` have identical file trees. The compact UI was safe locally and remotely, but missing from `main` at `198ca09`.

The `codex/player-reliability` integration targets `main` and includes both the full UI checkpoint and the reliability fixes. Once it is merged, no separate `codex/public-beta` integration PR is needed. Confirm the latest integration is on main before starting a baseline scan. Do not reset main, force-push, or revert/reapply the UI just to trigger a bot.

## Install Reviewers

Each service needs its own account and GitHub App authorization. Choose **Only select repositories**, then `AddarshKS/VibeCast`, instead of granting access to every repository. Review the current plan, trial, code-access permissions, and spending settings before enabling anything. Start with reviews only; leave automatic fixes and approvals off.

| Reviewer | Setup | Manual trigger on an open PR |
| --- | --- | --- |
| Greptile | Connect GitHub in Code Providers, select VibeCast, and enable it for reviews. Wait for indexing. | `@greptileai review this` |
| CodeRabbit | Sign in with GitHub, choose the personal account, then install/authorize its app for VibeCast. | `@coderabbitai full review` |
| cubic | Sign up and install its GitHub App for VibeCast. | `@cubic-dev-ai review this PR` |

Official instructions: [Greptile setup](https://www.greptile.com/docs/quickstart), [Greptile manual trigger](https://www.greptile.com/docs/code-review/custom-standards), [CodeRabbit GitHub setup](https://docs.coderabbit.ai/platforms/github-com), [CodeRabbit commands](https://docs.coderabbit.ai/faq), [cubic setup](https://docs.cubic.dev/ai-review/introduction).

## Review The Whole Repository

Indexing the repository for context is not the same as auditing every file. In particular, CodeRabbit's `full review` means the entire **PR**, not the entire repository. An empty PR against an identical main branch will not provide full-repository coverage. See [CodeRabbit's command scope](https://docs.coderabbit.ai/faq).

cubic has a dedicated **Codebase scans** feature for existing code. Its first scan audits the repository broadly rather than only a new diff. It is currently a request-access beta. Request access, confirm availability and cost, reconcile main first, then open VibeCast's Codebase scan page and select **Start scan**. Confirm the scan targets the intended branch/commit. Keep auto-remediation off initially and review the findings yourself. Scans can take hours and do not guarantee a bug-free app. [Official codebase-scan guide](https://docs.cubic.dev/codebase-scan/codebase-scans).

For Greptile and CodeRabbit, use ordinary reviews on the follow-up integration PR and future bug-fix PRs. Their repository-wide context is useful, but those reviews should not be labelled exhaustive audits of unchanged files. For a broader baseline review without scan access, review subsystems explicitly and track coverage; do not manufacture a destructive delete/re-add PR on main.

## VibeCast Review Instructions

Use these project-specific instructions in each reviewer's custom context/settings:

> Focus on reproducible correctness, cancellation, stale responses, Spotify restrictions, device ownership, account changes, bounded resources, and missing regression tests. Preserve the approved UI, spacing, transitions, and shared dropdown/window architecture. Do not redesign screens, add controls, replace Spotify's playback context, or implement request/Cast Magic work in a player-reliability PR. Recently Played is observed listening history, not an authoritative Spotify Previous stack. Never assume an HTTP 204 means playback has been observed, or an HTTP 403 means Premium is absent. Cite the exact code path and propose a focused test for each finding. Never expose credentials or enable live Spotify/AI tests without explicit authorization.

Provide `docs/PROJECT_STATUS.md`, `docs/COMPACT_DROPDOWN_EXPERIMENT.md`, and `docs/ARCHITECTURE_REVIEW.md` as context. Ignore generated `.build`, `.artifacts`, and `dist` content, but not the tests or packaging scripts.

## Review And Merge Discipline

My recommendation is to start with one automatic reviewer and use the others for targeted second opinions. Three automatic bots can produce overlapping comments and spend; compare their useful findings before keeping all three active.

For each finding, reproduce it, add a failing regression test when feasible, make the smallest fix, and rerun the relevant checks. Record false positives with an explanation. Require passing GitHub build/test checks and resolved review conversations before merging. Enable bot checks as required checks only after observing their actual names and behavior. Configure these rules explicitly in GitHub; this guide does not change repository permissions or merge rules.
