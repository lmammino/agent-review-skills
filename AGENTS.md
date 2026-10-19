# Guide for agents

This file explains how to change the skills in this repo without breaking them.

## What this repo contains

Two agent skills written in Markdown: `skills/adversarial-review/SKILL.md` and
`skills/reconcile-review/SKILL.md`. Each `SKILL.md` is the prompt an agent reads. There is no build
step.

## Rules for changes

- **Shared formats:** Both skills use the same priority legend, category identifiers, and comment
  prefix (`🟡 **Should fix** [<category>] — <finding>`). `reconcile-review` reads what
  `adversarial-review` posts, so change these in both skills and the README together.
- **Shared writing style:** Both skills have a "Writing style" section. Keep the rules aligned when
  you change one.
- **Examples:** Agents copy examples more closely than they follow rules. Every example comment,
  reply, and commit message must follow the writing style.
- **Length:** Every word of a `SKILL.md` is read on each use. A change that adds words should earn
  them.

## Writing style for the prompts

Use plain language in prompts, documentation, and examples.

- Lead with the main point.
- Use common words and active voice.
- Keep sentences and paragraphs short.
- Use one term for the same item.
- Avoid double negatives.
- Use periods, commas, colons, or parentheses instead of em dashes. The comment prefix and empty
  table cells keep their `—` because they are fixed formats.
- Keep exact identifiers, commands, paths, schema fields, and behavior-bearing examples.
