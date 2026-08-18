# Agent Review Skills

Two skills for multi-agent adversarial code review on GitHub PRs, using the `gh` CLI.

## Skills

### `adversarial-review`

Performs a thorough, adversarial code review on a GitHub PR. Reads the diff, description, and
existing comments, then posts verified inline findings prefixed with the agent's display label,
priority, and review category.
Deduplicates against other agents' comments and replies in-thread when disagreeing.

### `reconcile-review`

Triages and resolves review comments after one or more agents have reviewed a PR. Works in two
phases: **assess** (reads all comments, presents a resolution table with priority and category) and
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
- `jq` installed for safe review payload serialization
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
   configured display label and agents won't repeat each other
3. When agents disagree, they reply in-thread rather than creating noise
4. Run `/reconcile-review` to triage all comments, see a resolution table, and apply fixes

Actionable findings use one shared format across both skills:

```
**AGENT <display-name>:** 🟡 **Should fix** [tests] — <finding>
```

The shared priorities are 🔴 **Must fix**, 🟡 **Should fix**, 🟢 **Optional**, and ⚪️ **Good
practice**. Good-practice observations require no action and belong in the overall review summary.
During reconciliation, disproved and evidence-limited concerns use non-priority states so they do
not inflate actionable totals. A verified subjective preference may remain 🟢 **Optional** while
still needing human choice.

## Automating a multi-model review train

[`review-train.sh`](skills/adversarial-review/scripts/review-train.sh) (in
[`skills/adversarial-review/scripts/`](skills/adversarial-review/scripts/)) is a small shell
script that runs `/adversarial-review` against one PR across several models in sequence — each
review completing before the next starts — so you can cross-check findings and dedupe overlap
across models in a single command:

```bash
review-train.sh 42 openai-codex/gpt-5.6-sol glm-5.2:cloud deepseek-v4-pro:cloud qwen3.6:latest
```

It streams each model's output, reports which succeeded, and posts real inline comments to the
PR as each model runs. After the train, `/reconcile-review` can triage everything that was posted.

**It ships with the `adversarial-review` skill:** `npx skills add lmammino/agent-review-skills`
installs the script alongside the skill (to
`~/.agents/skills/adversarial-review/scripts/review-train.sh`), so once the skill is installed
the script is already on disk — just symlink it onto your `PATH`:

```bash
ln -sf ~/.agents/skills/adversarial-review/scripts/review-train.sh ~/.local/bin/review-train.sh
```

See [`skills/adversarial-review/scripts/README.md`](skills/adversarial-review/scripts/README.md)
for full install + usage details.

> **Note:** The `skills` CLI does not have a built-in mechanism for installing scripts or
> executables onto the user's `PATH`. It only copies skill directories (including `SKILL.md`
> and any bundled files like `scripts/`) into agent-specific locations. Symlinking the script
> into a directory already on your `PATH` (such as `~/.local/bin/`) is the standard approach.

### Troubleshooting: "Model not found"

If you see an error like this:

```
Error: Model "kimi-k2.7-code:cloud" not found. Use --list-models to see available models.
```

the model id you passed doesn't match any model available in your `pi` installation.
`review-train.sh` now performs a **pre-flight check** — it runs `pi --list-models` and validates
every requested model *before* launching any review. If any model is invalid, it lists the
available models and exits immediately (code 2), so no partial reviews are posted to the PR.

Common causes and fixes:

- **Typo or wrong model name**: run `pi --list-models` to see what's available.
- **Missing provider**: a bare id (e.g. `gpt-5.6-sol`) may resolve to a provider you have no
  key for. Qualify it with the provider: `openai-codex/gpt-5.6-sol`.
- **Cloud model not configured**: `*:cloud` models require the corresponding provider to be
  set up (e.g. `pi /login openai-codex`). See the
  [Pi documentation](https://github.com/earendil-works/pi-coding-agent) for setup.

## License

MIT
