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

```bash
npx skills add lmammino/agent-review-skills
```

Or install specific skills:

```bash
npx skills add lmammino/agent-review-skills --skill adversarial-review
npx skills add lmammino/agent-review-skills --skill reconcile-review
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

## License

MIT
