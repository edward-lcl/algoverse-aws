# Contributing

## Reporting issues

If you hit a problem during setup or while using the submit script, [open a GitHub issue](https://github.com/edward-lcl/algoverse-aws/issues/new) with:

1. **What you ran** — the exact command or step
2. **What you expected** — what should have happened
3. **What actually happened** — the full error message (not just the last line)
4. **Your environment** — OS, AWS region, instance type you're targeting

Issues are how this repo improves. If you hit a wall, someone else will hit the same wall.

## Common issues to report

These are the areas most likely to have rough edges:

- `setup.sh` fails on a specific OS or shell
- AWS quota request process changed (AWS updates these periodically)
- Instance type pricing/availability changed
- Dry-run passes but actual job fails
- Windows/WSL2 behavior differences

## Improving the docs

If something in the docs is unclear or wrong, a PR with the fix is welcome. Docs live in `docs/` — plain markdown, no build step needed.

## Adding an example

If you've used this bootstrap for a project (computer vision, NLP, time series, anything), add a directory under `examples/<your-project-type>/` with a brief README explaining the S3 layout and any project-specific wiring. Other teams benefit from seeing real patterns.

## What not to change without discussion

- The `setup.sh` core flow (budget → S3 → IAM → quota) — this order matters for cost safety
- The `AGENTS.md` operating contract rules (the negatives section) — these prevent the agent from doing things that would surprise users
- The `.gitignore` entry for `*.env` — credentials must never be committed
