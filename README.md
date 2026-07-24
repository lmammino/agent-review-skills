# Agent Review Skills

Two skills for multi-agent adversarial code review on GitHub PRs, using the `gh` CLI.

## Skills

### `adversarial-review`

Performs a thorough, adversarial code review on a GitHub PR. Reads the diff, description, and
existing comments, then posts inline review comments prefixed with the agent's model name.
Deduplicates against other agents' comments and replies in-thread when disagreeing.

### `reconcile-review`

Triages and resolves review comments after one or more agents have reviewed a PR. Works in two
phases: **assess** (reads all comments, presents a resolution table with severity ratings) and
**apply** (user selects which resolutions to apply, agent makes the changes and pushes).

## Install

Install both skills with:

```bash
npx skills add lmammino/agent-review-skills
```

Or install a specific skill:

```bash
npx skills add lmammino/agent-review-skills --skill adversarial-review
npx skills add lmammino/agent-review-skills --skill reconcile-review
```

To install globally (available across all projects), add the `-g` flag:

```bash
npx skills add lmammino/agent-review-skills --skill adversarial-review -g
```

> **Note:** Some agents (e.g. PromptScript) do not support global skill installation. In that case,
> install the skill at project scope instead.

To update a previously installed skill to the latest version:

```bash
# Project scope (default)
npx skills update -p

# Global scope
npx skills update -g
```

Or reinstall the specific skill directly:

```bash
npx skills add lmammino/agent-review-skills --skill adversarial-review -g -y
```

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status`)
- Inside a git clone of the target repository

## Usage

In your coding agent (Claude Code, Codex, Cursor, etc.):

```
/adversarial-review 42        # Review PR #42
/reconcile-review 42          # Triage and resolve comments on PR #42
```

To identify the reviewer agent in multi-model workflows, either set the `AGENT_DISPLAY_NAME`
environment variable or pass an explicit label as a second argument:

```bash
AGENT_DISPLAY_NAME=claude-sonnet-4-20250514 /adversarial-review 42
/adversarial-review 42 gpt-5
```

When both are provided, the explicit argument takes precedence.

## How it works

1. Run `/adversarial-review` with a PR number to have an agent post an adversarial review
2. Run it again with a **different model** for a second opinion — comments are prefixed with the
   model name and agents won't repeat each other
3. When agents disagree, they reply in-thread rather than creating noise
4. Run `/reconcile-review` to triage all comments, see a resolution table, and apply fixes

## Automating a multi-model review train

[`review-train.sh`](https://gist.github.com/lmammino/22eb1810bc941bcdd31b2b833130d07f) is a
small shell script that runs `/adversarial-review` against one PR across several models in
sequence — each review completing before the next starts — so you can cross-check findings and
dedupe overlap across models in a single command:

```bash
review-train.sh 42 glm-5.2:cloud deepseek-v4-pro:cloud qwen3.6:latest
```

It streams each model's output, reports which succeeded, and posts real inline comments to the
PR as each model runs. After the train, `/reconcile-review` can triage everything that was posted.
See the gist for install + usage details.

## License

MIT
