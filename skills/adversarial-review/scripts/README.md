# review-train.sh

Run the [`pi`](https://github.com/earendil-works/pi-coding-agent) `adversarial-review` skill
against a single GitHub PR across multiple models — **sequentially**, each review completing
before the next one starts. `review-train.sh` automates launching a whole train of those reviews
in one command.

It is a companion to the parent [`adversarial-review`](../SKILL.md) skill and **ships with it**:
installing the skill also installs this script.

## Install

### With the skill (recommended)

If you install the `adversarial-review` skill, this script comes with it:

```bash
npx skills add lmammino/agent-review-skills --skill adversarial-review -g
```

The script lands at `~/.agents/skills/adversarial-review/scripts/review-train.sh` (and is
reachable through the `pi` symlink at
`~/.pi/agent/skills/adversarial-review/scripts/review-train.sh`). To call it as `review-train.sh`
from any directory, symlink it onto your `PATH`:

```bash
ln -sf ~/.agents/skills/adversarial-review/scripts/review-train.sh ~/.local/bin/review-train.sh
```

> GitHub release archives don't preserve the executable bit, so if `review-train.sh` complains
> about permission, grant it once:
>
> ```bash
> chmod +x ~/.agents/skills/adversarial-review/scripts/review-train.sh
> ```
>
> Or run it in place without the exec bit: `bash ~/.agents/skills/adversarial-review/scripts/review-train.sh …`

### Standalone

If you only want the script (without installing the skill), clone the repo and copy the
script onto your `PATH`:

```bash
git clone https://github.com/lmammino/agent-review-skills.git /tmp/agent-review-skills
cp /tmp/agent-review-skills/skills/adversarial-review/scripts/review-train.sh ~/.local/bin/
chmod +x ~/.local/bin/review-train.sh
```

> **Why not `curl` a raw file?** Downloading and executing a shell script directly from
> `raw.githubusercontent.com` is flagged by security scanners (Snyk E005) as a high-risk
> pattern — it's the same vector used in supply-chain attacks. Cloning the repo first lets
> you inspect the script before running it, and the commit history provides an audit trail.

## Usage

```bash
cd <target-repo>
review-train.sh [--shuffle] <pr-id> <model-id> [<model-id> ...]
```

Each `<model-id>` is passed to `pi --model` (the runner); its model part (after the last `/`) is
used as the skill's display-name argument, so every review is attributed to a distinct agent
prefix.

Pass `--shuffle` to randomize the order of the models before the train runs. If you reuse
the same command across PRs, the models you list first always run first and their reviews land
on the PR before the later ones start — which can bias the later models in the queue (they see
the earlier reviews' inline comments while forming their own). Shuffling spreads that first-mover
effect across models run to run instead of concentrating it on the same one. The flag may appear
anywhere in the argument list and is a no-op for a single model.

### Model ids & providers

A bare id like `glm-5.2:cloud` lets pi's fuzzy resolver pick the provider. That's fine when the
model only lives on one provider you're authenticated for, but a model available on several
providers (e.g. `gpt-5.6-sol`) may resolve to one you have **no key for** (pi exits with
`No API key found for <provider>`). Pass the id **provider-qualified** (`provider/model`) to pin
the authenticated provider — the provider prefix is stripped from the review's agent name.

For an **OpenAI ChatGPT Plus/Pro subscription**, log in once with `pi` (`/login openai-codex`),
then qualify the id with the `openai-codex` provider:

```bash
review-train.sh 116 openai-codex/gpt-5.6-sol glm-5.2:cloud deepseek-v4-pro:cloud
```

The first review runs as `gpt-5.6-sol` (via your ChatGPT subscription); the others via local
Ollama. Discover available ids per provider with `pi --list-models | grep <provider>`.

### Example

```bash
review-train.sh 115 glm-5.2:cloud deepseek-v4-pro:cloud qwen3.6:latest
```

runs three sequential reviews of PR #115, one per model, posting inline comments to the PR.

With `--shuffle` the same three models are run in a randomized order:

```bash
review-train.sh --shuffle 115 glm-5.2:cloud deepseek-v4-pro:cloud qwen3.6:latest
```

## Requirements

- [`pi`](https://github.com/earendil-works/pi-coding-agent) on `PATH`.
- [`gh`](https://cli.github.com/) on `PATH` and authenticated (`gh auth login`).
- Run from **inside the target repo's working tree** (the skill needs a git clone + `gh` auth,
  and it posts real review comments to the PR as each model runs).
- *(optional)* [`glow`](https://github.com/charmbracelet/glow) on `PATH` — when installed and stdout is
  a terminal, each model's output is rendered as markdown with glow instead of the plain dim
  style. Not required; the script falls back to the dim style automatically.

## Behavior

- **Sequential:** each `pi -p` invocation is non-interactive and blocks until the review
  completes, so the next model only starts after the previous one finishes.
- **Shuffleable:** pass `--shuffle` to randomize the run order of the models. This spreads
  the first-mover bias (earlier reviews are visible to later models in the queue) across models
  run to run, instead of always concentrating it on the same one. No-op for a single model.
- **Fault-tolerant:** one model failing does **not** abort the train. Failed models are
  collected and reported in the summary; the script exits `1` if any failed.
- **Pre-flight model validation:** before launching any review, the script runs `pi --list-models`
  and checks every requested model id against the result. If any model is not found, it prints
  the invalid id(s), lists the available models, and exits with code 2 — **before** posting any
  comments to the PR. This prevents the scenario where the first model starts, fails with
  `Model "…" not found`, and the user must Ctrl-C the rest of the train.
- **Per-run emoji:** each agent run is introduced by a random train emoji.
- **Agent output rendering:** when stdout is a terminal, each model's streamed output is passed
  through [`glow`](https://github.com/charmbracelet/glow) if installed (rendered as markdown,
  appearing when the review completes since glow buffers), otherwise through a dim style so it
  reads as fainter than the script's own status headers. When stdout is not a terminal (e.g.
  redirected to a log), output is plain for clean capture.
- **Per-model output** is reported with `✓`/`✗` status and elapsed time.

## Exit codes

| Code | Meaning |
|------|---------|
| `0`  | every review succeeded |
| `1`  | one or more reviews failed |
| `2`  | bad usage (missing args, non-numeric pr-id, PR not found, model(s) not found) or environment not ready |

## Notes

- Each run posts **real inline comments** to the PR — point it at a PR you're happy to receive
  reviews on.
- After a train, run the sibling [`reconcile-review`](../../reconcile-review/SKILL.md) skill to
  triage everything that was posted into a resolution table and apply the fixes you approve.
- Model ids follow whatever `pi --model` accepts. Bare ids work when the model lives on a single
  authenticated provider; qualify with `provider/model` when the same id exists on multiple
  providers.