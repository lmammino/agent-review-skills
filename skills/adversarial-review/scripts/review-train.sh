#!/usr/bin/env bash
# review-train.sh — run the pi `adversarial-review` skill against one PR across several models,
# sequentially: each review runs to completion before the next one starts.
#
# This script ships with the adversarial-review skill: `npx skills add lmammino/agent-review-skills`
# installs it to ~/.agents/skills/adversarial-review/scripts/review-train.sh (symlinked from
# ~/.pi/agent/skills/adversarial-review/scripts/). See scripts/README.md for install + usage.
#
# Usage:
#   review-train.sh [--shuffle] <pr-id> <model-id> [<model-id> ...]
#
# Arguments:
#   pr-id     GitHub PR number in the current repo.
#   model-id  A pi model id. Pass it provider-qualified (e.g. "openai-codex/gpt-5.6-sol") to pin
#             the authenticated provider — a bare id lets pi's fuzzy resolver pick a provider,
#             which may be one you have no key for. The part after the last "/" becomes the
#             skill's display-name argument (the review's agent prefix), so
#             "openai-codex/gpt-5.6-sol" is attributed to "gpt-5.6-sol".
#
# Flags:
#   --shuffle  Randomize the order of the models before running the train. Useful to avoid
#              systemic ordering bias (e.g. always running the same model first). The flag may
#              appear anywhere in the argument list.
#
# Run from inside the target repo's working tree. The skill needs a git clone plus an
# authenticated `gh`, and it posts inline review comments to the PR as each model runs.
#
# Exit status: 0 if every review succeeded, 1 if any failed, 2 on bad usage/environment.

set -u
set -o pipefail # a failing `pi` inside `... | sed` surfaces as the pipeline's exit code
# Deliberately no `set -e`: one model failing must not abort the rest of the train.

# Dim the agent's streamed output so it reads as fainter than this script's status headers.
# Only emit color when stdout is a terminal (keeps logs and redirects clean).
if [ -t 1 ]; then
  DIM=$'\033[2m'
  RESET=$'\033[0m'
else
  DIM=''
  RESET=''
fi

# If glow (https://github.com/charmbracelet/glow) is installed and stdout is a terminal, render
# the agent's markdown output with it; otherwise fall back to the dim style. glow buffers, so its
# rendered output appears when the review completes rather than streaming live.
USE_GLOW=0
if [ -t 1 ] && command -v glow >/dev/null 2>&1; then
  USE_GLOW=1
fi

# One random train emoji per agent run, drawn from this set.
TRAINS=(🚞 🚂 🚄 🚅 🚃 🚟 🚝 🚈)

# Render the agent's streamed output: glow when available, else the dim style.
render_output() {
  if [ "$USE_GLOW" -eq 1 ]; then
    glow -
  else
    sed "s|^|$DIM|; s|$|$RESET|"
  fi
}

usage() {
  printf 'Usage: %s [--shuffle] <pr-id> <model-id> [<model-id> ...]\n' "$0" >&2
  printf 'Run from inside the target repo. Each model reviews the PR in sequence.\n' >&2
  printf 'Pass --shuffle to randomize the order of the models first.\n' >&2
  exit 2
}

# --- environment guards -------------------------------------------------------
command -v pi >/dev/null 2>&1 || { printf 'pi not found on PATH\n' >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { printf 'gh not found on PATH\n' >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { printf 'not inside a git work tree — cd into the target repo first\n' >&2; exit 1; }
gh auth status >/dev/null 2>&1 \
  || { printf 'gh not authenticated (run: gh auth login)\n' >&2; exit 1; }

# --- argument parsing ---------------------------------------------------------
[ $# -ge 2 ] || usage
SHUFFLE=0
args=()
for arg in "$@"; do
  case "$arg" in
    --shuffle) SHUFFLE=1 ;;
    --shuffle=*) case "${arg#--shuffle=}" in 1|true|yes|on) SHUFFLE=1 ;; *) SHUFFLE=0 ;; esac ;;
    --help|-h) usage ;;
    --) shift; while [ $# -gt 0 ]; do args+=("$1"); shift; done; break ;;
    --*) printf 'unknown flag: %s\n' "$arg" >&2; exit 2 ;;
    *) args+=("$arg") ;;
  esac
done
set -- "${args[@]}"

[ $# -ge 2 ] || usage
case "$1" in
  ''|*[!0-9]*) printf 'pr-id must be a positive integer, got: %s\n' "$1" >&2; exit 2 ;;
esac
PR_ID="$1"; shift
MODELS=("$@")

if [ "$SHUFFLE" -eq 1 ] && [ "${#MODELS[@]}" -gt 1 ]; then
  # Fisher–Yates shuffle so the run order is randomized instead of as given on the CLI.
  for ((i = ${#MODELS[@]} - 1; i > 0; i--)); do
    j=$((RANDOM % (i + 1)))
    tmp="${MODELS[i]}"; MODELS[i]="${MODELS[j]}"; MODELS[j]="$tmp"
  done
fi

# Fail fast before launching any model: the PR must exist in the current repo.
gh pr view "$PR_ID" --json number >/dev/null 2>&1 \
  || { printf 'PR #%s not found in %s\n' "$PR_ID" "$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo 'this repo')" >&2; exit 2; }

# Pre-flight: validate that every model id is available in pi before starting the train.
# This avoids the scenario where the first model launches, fails with "Model not found",
# and the user has to Ctrl-C the rest. We build a lookup set from `pi --list-models` and
# check each requested model against it.
printf '🔍 pre-flight: validating %d model(s)…\n' "${#MODELS[@]}" >&2
AVAILABLE_MODELS=$(pi --list-models 2>/dev/null) || { printf 'failed to list models (pi --list-models)\n' >&2; exit 1; }
invalid_models=()
for model in "${MODELS[@]}"; do
  # pi --list-models prints one model id per line (possibly provider-qualified as provider/model).
  # We check both the full id and the model-only part (after the last "/") for a match.
  bare="${model##*/}"
  if ! printf '%s\n' "$AVAILABLE_MODELS" | grep -qxF "$model" && \
     ! printf '%s\n' "$AVAILABLE_MODELS" | grep -qxF "$bare"; then
    invalid_models+=("$model")
  fi
done
if [ ${#invalid_models[@]} -gt 0 ]; then
  printf '✗ pre-flight: %d model(s) not found:\n' "${#invalid_models[@]}" >&2
  for m in "${invalid_models[@]}"; do
    printf '  • %s\n' "$m" >&2
  done
  printf '\nAvailable models (pi --list-models):\n%s\n' "$AVAILABLE_MODELS" >&2
  printf '\nTip: use a provider-qualified id (e.g. openai-codex/gpt-5.6-sol) to pin a\n' >&2
  printf 'specific provider — a bare id may resolve to one you have no key for.\n' >&2
  exit 2
fi
printf '✓ pre-flight: all models available\n\n' >&2

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo '?')
if [ "$SHUFFLE" -eq 1 ]; then
  printf '🚂 review train: PR #%s on %s — %d model(s): %s (shuffled order)\n\n' \
    "$PR_ID" "$REPO" "${#MODELS[@]}" "${MODELS[*]}"
else
  printf '🚂 review train: PR #%s on %s — %d model(s): %s\n\n' \
    "$PR_ID" "$REPO" "${#MODELS[@]}" "${MODELS[*]}"
fi

# --- the train ----------------------------------------------------------------
failed=()
idx=0
for model in "${MODELS[@]}"; do
  idx=$((idx + 1))
  # Runner = the full id (provider-qualified when needed to pin the authenticated provider).
  # Display = the model part after the last "/", used as the skill's agent prefix so a
  # qualified id like "openai-codex/gpt-5.6-sol" is attributed to "gpt-5.6-sol".
  runner="$model"
  display="${model##*/}"
  train="${TRAINS[$((RANDOM % ${#TRAINS[@]}))]}"
  printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
  printf '%s [%d/%d] %s — starting (pi --model %s)\n' "$train" "$idx" "${#MODELS[@]}" "$display" "$runner"
  start=$(date +%s)
  # `pi -p` is non-interactive: it runs the skill to completion, then exits. Its output is rendered
  # by `render_output` (glow if installed, else dim) so the review work reads as fainter than this
  # script's status headers; `pipefail` makes a `pi` failure surface through the render pipe.
  if pi -p --model "$runner" "/skill:adversarial-review $PR_ID $display" 2>&1 | render_output; then
    printf '✓ [%d/%d] %s — done in %ds\n' "$idx" "${#MODELS[@]}" "$display" "$(( $(date +%s) - start ))"
  else
    rc=$?
    printf '✗ [%d/%d] %s — FAILED (exit %d) after %ds\n' "$idx" "${#MODELS[@]}" "$display" "$rc" "$(( $(date +%s) - start ))"
    failed+=("$display")
  fi
done

# --- summary ------------------------------------------------------------------
printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
succeeded=$(( ${#MODELS[@]} - ${#failed[@]} ))
printf '🚂 train complete: %d/%d succeeded\n' "$succeeded" "${#MODELS[@]}"
if [ ${#failed[@]} -gt 0 ]; then
  printf '✗ failed: %s\n' "${failed[*]}"
  exit 1
fi
exit 0