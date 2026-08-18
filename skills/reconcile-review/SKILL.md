---
name: reconcile-review
description: Triage and resolve review comments on a GitHub PR. Reads all comments, assesses each one, and presents a resolution table. The user can then approve, modify, or reject resolutions, and the agent applies the chosen changes.
---

# Reconcile Review

## Overview

After one or more agents (or humans) have reviewed a PR, this skill triages all the review
comments and suggests resolutions. It works in two phases:

1. **Assess phase**: reads all PR comments, understands each issue in context, and presents a
   structured resolution table in the terminal.
2. **Apply phase**: the user reviews the table, selects which resolutions to apply, and the agent
   makes the code changes, optionally replying to comment threads and marking them as resolved.

## Prerequisites

- `gh` CLI must be installed and authenticated (`gh auth status`).
- The current working directory must be inside a git clone of the target repository, on the PR's
  source branch (or a checkout of it).

## Input

A GitHub PR number (e.g. `42`) or URL (e.g. `https://github.com/owner/repo/pull/42`).

---

## Phase 1: Assess

### 1. Gather all comments

```bash
# PR metadata
gh pr view <number> --json title,body,baseRefName,headRefName,author,state

# All review comments (inline + replies)
gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/pulls/<number>/comments" --paginate

# General PR comments
gh pr view <number> --comments --json comments

# The diff (for context when assessing each comment)
gh pr diff <number>
```

### 2. Check out the PR branch

```bash
gh pr checkout <number>
```

This is needed so you can read the full files (not just the diff) when assessing comments and
making changes later. All changes will be committed directly to this branch — this is iterative
feedback on the PR, not a separate review branch.

### 3. Categorize and assess each comment thread

Group comments by thread (top-level review comment + its replies). For each thread:

- **Read the surrounding code** in the full file, not just the diff hunk.
- **Understand the concern** — what is the commenter asking for?
- **Determine the severity**: bug, security, design, performance, testing gap, style nit, or
  subjective preference.
- **Decide a resolution**: accept (make the suggested change), reject (explain why not), or
  propose an alternative (a different fix for the same concern).

### 4. Present the resolution table

Output a markdown table in the terminal. Each row represents one comment thread:

```
| # | File | Line | Author | Concern | Severity | Suggested Resolution |
|---|------|------|--------|---------|----------|---------------------|
| 1 | src/foo.ts | 42 | AGENT claude | Null check missing | 🔴 bug | Accept: add guard clause |
| 2 | src/bar.ts | 15 | AGENT gpt-5 | Use const instead of let | 🟢 style | Accept: change to const |
| 3 | src/baz.ts | 8 | human-reviewer | Extract this to a helper | 🟡 design | Alternative: extract but keep in same file |
| 4 | src/qux.ts | 100 | AGENT claude | Add error handling | 🔴 bug | Accept: wrap in try/catch |
```

Severity legend:
- 🔴 **bug** — incorrect behavior, crash, security issue, data loss
- 🟡 **design** — architectural concern, maintainability, technical debt
- 🟢 **style** — naming, formatting, minor cleanup
- ⚪ **subjective** — personal preference, no clear right answer

After the table, print a summary:
- Total comment threads found.
- Breakdown by severity.
- Number of threads where agents disagree with each other (these need human judgment).

For threads where agents disagree, highlight them and explain both sides:

```
### Disagreements needing human judgment

**Thread #5 — src/foo.ts:42**
- **AGENT claude:** Extract this logic to a separate function.
- **AGENT gpt-5 (reply):** Disagree — the logic is only 3 lines and extracting it adds indirection.
- **Suggested resolution:** ⚪ subjective — your call. If this logic is reused elsewhere, extract it.
```

### 5. Wait for user input

After presenting the table, ask the user how to proceed. They can say:

- "apply all" — apply every suggested resolution
- "apply 1, 3, 5" — apply only specific threads
- "reject 4" — mark thread 4 as won't-fix (reply with explanation)
- "change 2 to use let instead" — modify a resolution before applying
- "skip 6" — leave thread 6 unresolved for now

---

## Phase 2: Apply

### 1. Make code changes

For each accepted resolution, edit the file(s) to implement the fix. Follow the repo's conventions
(code style, commit message format, etc.).

### 2. Reply to comment threads (optional but recommended)

After making changes, reply to each resolved thread explaining what was done:

```bash
gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/pulls/<number>/comments" \
  -f body="Resolved in [commit hash]: <brief description of the change>." \
  -f in_reply_to="<comment-database-id>"
```

### 3. Mark threads as resolved (optional)

GitHub does not expose a REST API to resolve comment threads. The "resolve conversation" button
in the UI calls a GraphQL mutation. To resolve threads programmatically, you need the thread's
GraphQL node ID.

**Step 1: Find the thread node ID for each comment**

First, get the review thread ID from a comment's `node_id` using a GraphQL query:

```bash
# For a single comment, look up its pull request review thread
gh api graphql -f query='
  query($commentId: ID!) {
    node(id: $commentId) {
      ... on PullRequestReviewComment {
        pullRequestReview {
          comments(first: 50) {
            nodes {
              id
              body
            }
          }
        }
      }
    }
  }
' -f commentId="<comment-node-id>"
```

Alternatively, list all review threads on the PR directly:

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 10) {
              nodes {
                body
                author { login }
              }
            }
          }
        }
      }
    }
  }
' -f owner="<owner>" -f repo="<repo>" -f pr=<number>
```

Match threads to your comment table by comparing the comment body text.

**Step 2: Resolve each thread**

```bash
gh api graphql -f query='
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) {
      thread { isResolved }
    }
  }
' -f threadId="<thread-node-id>"
```

**Simpler alternative**: if you push a commit that modifies the exact line a comment is anchored
to, GitHub auto-resolves that thread. This is often easier than the GraphQL approach — just make
sure your code changes touch the commented lines.

### 4. Commit and push

After all changes are made, commit with a descriptive message referencing the PR:

```bash
git add -A
git commit -m "Address review feedback for PR #<number>

- Fix null check in src/foo.ts (thread #1)
- Change let to const in src/bar.ts (thread #2)
- ..."
git push
```

### 5. Final summary

Report what was done:
- Number of threads resolved.
- Number of threads rejected (with reasons).
- Number of threads left unresolved (needing human judgment).
- Link to the PR.

---

## Edge cases

- **No comments found**: report that the PR has no review comments and stop.
- **PR is closed/merged**: warn the user but proceed if they confirm (comments can still be
  addressed in a follow-up PR).
- **Merge conflicts**: if the PR branch has conflicts with the base, warn the user before making
  changes. Resolve conflicts if the user asks.
- **Agent disagreements**: always flag these for human judgment rather than picking a side
  automatically.

## Writing style

When writing resolution table descriptions, reply comments, and commit messages:

- **Write in plain, accessible English.** Use simple words and short sentences. Avoid jargon,
  metaphor, and unnecessarily formal or literary language. Write for a global audience — many
  readers are not native English speakers. Explain concepts so that someone unfamiliar with the
  codebase or the business domain can follow along.

## Constraints

- Do not force-push or rebase without explicit user approval.
- Do not resolve threads that the user asked to skip.
- Never log or include secrets, tokens, or PII in commit messages or comment replies.
