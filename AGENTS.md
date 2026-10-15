# AGENTS.md

Working notes for AI coding agents in baskingspot/gh-actions.

## What this is

The shared workflows for every baskingspot repo, and the maintenance job that opens flake.lock and action-pin pull requests across the org. It is the reference implementation of org CI, so each repo's workflows should look like the ones here.

## Environment

The flake is the tool contract. `nix develop` provides actionlint, zizmor, pinact, just, oxfmt, and nixfmt, and the `.envrc` loads it through direnv. If a tool is missing, add it to the flake.

The justfile is the command interface:

```
just lint
just ci
```

`just ci` runs what the CI workflow runs: formatting, actionlint, and zizmor. Run `just fmt` before you commit.

## Layout

- `.github/workflows/ci.yml` and `zizmor.yml` are reusable (`workflow_call`) and also run on this repo's own pushes.
- `.github/workflows/maintain.yml` is the weekly job. It runs only on a schedule or by hand.
- `docs/static/` holds this repo's logos, from `just new-library` in the `.github` repo.

## Conventions

- Pin every `uses:` by commit SHA with a version comment. Use `just pin` to pin a new one and `just update` to move them all. Both need `GITHUB_TOKEN`.
- Start every workflow with `permissions: {}` and grant each job only what it needs.
- Never put a `${{ }}` expression inside a `run:` script. Pass it through `env:`.
- zizmor must pass. Suppress a finding only with an inline `# zizmor: ignore[rule]` comment and a sentence above it that says why.
- Mint GitHub App tokens per job, for one repo, with the least permissions the job needs. Only the pin-update job gets `workflows: write`.
- Add a maintenance task by adding a `task` value in the `discover` job and the steps that handle it in the `update` job.
- Recipes carry a `[doc("...")]` directive and a `[group("...")]`. Commit messages are one line, `area: summary`. Every commit is signed. Do not rewrite pushed history.
- Public text follows the org voice guide in the `.github` repo, `docs/VOICE.md`.
