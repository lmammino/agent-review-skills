---
name: adversarial-review
description: Perform an adversarial code review on a GitHub PR. Reads the diff, description, and existing comments, then posts inline review comments with a unique agent prefix. Deduplicates against other agents' comments and replies in-thread when disagreeing.
---

# Adversarial Review

## Overview

Perform a thorough, adversarial code review on a GitHub pull request. The agent reads the PR
description, the full diff, and all existing review comments, then posts **inline review comments**
on the PR. Each comment is prefixed with the agent's model name so multiple agents can review the
same PR without confusion.

The review is **adversarial**: go beyond surface-level nits. Look for logic errors, edge cases,
security issues, race conditions, performance problems, missing tests, API contract violations,
and architectural concerns. Challenge assumptions stated in the PR description.

## Prerequisites

- `gh` CLI must be installed and authenticated (`gh auth status`).
- The current working directory must be inside a git clone of the target repository.

## Input

A GitHub PR number (e.g. `42`) or URL (e.g. `https://github.com/owner/repo/pull/42`).

## Steps

### 1. Gather PR information

Run these commands and capture their output:

```bash
# PR metadata (title, body, base/target branch, author, state)
gh pr view <number> --json title,body,baseRefName,headRefName,author,state

# The full diff
gh pr diff <number>

# Existing review comments (top-level reviews + inline comments + replies)
gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/pulls/<number>/comments" --paginate
```

Also fetch any general PR comments (non-inline):

```bash
gh pr view <number> --comments --json comments
```

### 2. Determine agent identity

Use your own model name as the comment prefix. If an environment variable `AGENT_DISPLAY_NAME` is
set, use that instead. The prefix format is:

```
**AGENT <model-name>:** 
```

Examples: `**AGENT claude-sonnet-4-20250514:**`, `**AGENT gpt-5:**`

### 3. Analyze the changes

Read the diff carefully. For each file changed:

- Understand what the code does and why the change is being made (from the PR description).
- Look for: logic errors, missing edge cases, security vulnerabilities, race conditions,
  performance regressions, missing or inadequate tests, API contract breaks, error handling gaps,
  concurrency issues, resource leaks, and architectural concerns.
- Check that the PR description's claims match the actual changes.
- Review test files — are the tests meaningful or just coverage padding?
- Glance at the PR description for major gaps (missing test plan, unclear motivation, unstated
  breaking changes), but only flag these if they are significant — don't nitpick formatting.

**Comment budget**: aim for **5–15 substantive comments**. Prioritize bugs, security issues,
and design problems. Skip style nits, subjective preferences, and anything that could be
reasonably left to a linter. If you find more than 15 issues, post only the most impactful ones.
A short, high-signal review is more valuable than an exhaustive one.

### 4. Check existing comments (dedup)

Before writing a comment on any issue, check existing review comments:

1. **Same-line check**: if an existing comment is anchored to the same file and diff line, read
   it. If it raises the same concern, **skip** — do not repeat.
2. **Topic check**: scan all existing comments for overlapping concerns even on different lines.
   If the same issue is already raised elsewhere, skip.
3. **Disagreement**: if an existing agent comment is wrong or misses important context, **reply
   in that thread** rather than starting a new top-level comment. Start the reply with your
   agent prefix and explain why you disagree, providing additional context.

A comment is "similar" if it addresses the same underlying issue — not just the same words.
Use judgment: two comments about "null safety" on different lines may be the same concern if
they point to the same root cause.

### 5. Prepare and post the review

Post comments as a **review** (not individual standalone comments) so they appear as a batch:

```bash
gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/pulls/<number>/reviews" \
  -f event="COMMENT" \
  -f body="Optional overall review summary. Leave empty if all feedback is inline." \
  -f comments='[
    {
      "path": "src/file.ts",
      "line": 42,
      "side": "RIGHT",
      "body": "**AGENT claude-sonnet-4-20250514:** This is the comment body.\n\nConsider doing X instead of Y because Z."
    },
    {
      "path": "src/other.ts",
      "line": 10,
      "side": "RIGHT",
      "body": "**AGENT claude-sonnet-4-20250514:** Another concern here."
    }
  ]'
```

Key API fields:
- `path`: file path relative to repo root (as shown in the diff).
- `line`: the line number in the file on the **target side** of the diff (use `side: "RIGHT"` for
  new/modified lines, `side: "LEFT"` for deleted lines — LEFT is rarely needed).
- `body`: the comment text. Always start with the agent prefix.
- `start_line` + `start_side`: optional, for multi-line range comments.
- `in_reply_to`: set this to an existing comment's database ID to reply in-thread instead of
  creating a new top-level thread.

To reply to an existing comment thread (disagreement), use the `in_reply_to` field or post a
reply via:

```bash
gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/pulls/<number>/comments" \
  -f body="**AGENT claude-sonnet-4-20250514:** I disagree because..." \
  -f in_reply_to="<comment-database-id>"
```

### 6. Summary

After posting, report:
- Number of new comments posted.
- Number of issues skipped (already covered by another agent).
- Any disagreement replies made.

## Comment guidelines

- **Be specific.** Reference exact line numbers, variable names, and edge cases.
- **Be constructive.** Suggest a concrete fix or alternative approach.
- **Explain the "why."** Don't just say "this is wrong" — explain the failure mode.
- **Prioritize.** Focus on bugs, security issues, and design problems over style nits.
- **Keep comments self-contained.** Each comment should be understandable without reading others.
- **Never log or include secrets, tokens, or PII** in comment bodies.

## Constraints

- Only post comments on the PR — do not push commits or modify the branch.
- Do not repeat concerns already raised by another agent.
- If the PR is closed or merged, report that and stop.
- Aim for 5–15 comments. If you have more, keep only the most impactful ones.
- Do not comment on style or formatting issues that a linter would catch.
