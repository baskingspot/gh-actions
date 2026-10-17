# AGENTS.md

Working notes for AI coding agents in baskingspot/gh-actions.

## What this is

The shared workflows for every baskingspot repo, and the maintenance job that pushes flake.lock and action-pin updates to every org repo's default branch. It is the reference implementation of org CI, so each repo's workflows should look like the ones here.

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

- Pin every `uses:` by commit SHA with a version comment. Use `just pin` to pin a new one and `just update` to move them all. Both need `GITHUB_TOKEN`. The three-day age rule applies to other owners' actions only. Our own `baskingspot/` actions are exempt, because a trailing delay here would stack on every repo that calls us.
- Pin the runner label, `runs-on: ubuntu-26.04`, never `ubuntu-latest`. A moving label changes the OS under us and prints a migration warning. Nothing bumps the label for us, so a new Ubuntu LTS is a deliberate edit.
- The shared `ci.yml` takes `runners` and `recipes`, JSON arrays, and runs a matrix of both. Keep it backwards compatible: a repo that passes nothing gets `ci` on `ubuntu-26.04` only, because the maintenance job bumps every caller to a new release at once. Never rename or remove an input in a release a caller may already use.
- `maintain.yml` touches only repos whose org custom property `stage` is `stable`, which is the default. `incubating` is a repo being hacked on, and `mirror` is a working copy that has to stay identical to upstream, such as `zigdoc-wip`. The repo list API carries the property, so the bot needs no extra permission.
- A commit body written by the bot is the result, never a tool's whole output. Each task builds `body.md` from the lines that matter (the moved inputs, the pin summary), and the push step caps it at 4000 bytes. Filter the output of any new task the same way.
- The `images` task finds a repo by a root `Dockerfile` and runs `scripts/pin-images.sh`. The script is shell with a no-network test (`just test`). It touches only `FROM` lines and `*IMAGE` assignments, so extend its patterns with a test in the same change.
- Every `uses:` is pinned by SHA with a release tag in the comment, such as `# v0.7.0`. A comment like `# main` makes `pinact` refuse the whole file, and norm's pins task then fails for this repo. When a workflow here needs a new commit of one of its own actions, release first, then pin the release.
- `release.yml` is the only publish path. A new channel is a new job after `publish`, and it must test before it writes. The cask is rendered by `scripts/render_cask.py`, through the `actions/render-cask` composite action, and the tap holds nothing but casks. `release.yaml` keys are validated in the `plan` job: add a key there and in the test in the same change. The archive layout and the notes are dictated by `scripts/package.sh` and `scripts/release-notes.sh`, with tests. A program's recipe only builds: `just release-build TARGET DIR` installs into the prefix DIR, so its files land in DIR/bin. Platforms are a fixed set, and Windows is shipped as a zip and goes through no other channel. A program that ships needs `APP_PRIVATE_KEY` and `APP_CLIENT_ID` access, granted per repo.
- `deploy-docs.yml` is the one workflow that touches Cloudflare. It deploys with a token scoped to one Worker, and the caller passes it. Keep it free of anything specific to a repo.
- Start every workflow with `permissions: {}` and grant each job only what it needs.
- Never put a `${{ }}` expression inside a `run:` script. Pass it through `env:`.
- zizmor must pass. Suppress a finding only with an inline `# zizmor: ignore[rule]` comment and a sentence above it that says why.
- Mint GitHub App tokens per job, for one repo, with the least permissions the job needs. Only the pin-update job gets `workflows: write`.
- Nix is installed with `cachix/install-nix-action`, pinned to one Nix release through `install_url`, and cached with `cachix/cachix-action` into the `baskingspot` cache. Only a run on the default branch pushes to the cache.
- The maintenance job commits straight to the default branch with GitHub's `createCommitOnBranch` API, so the commit is signed by the App. It runs the repo's `just ci` first and pushes nothing if that fails.
- Add a maintenance task by adding a `task` value in the `discover` job and the steps that handle it in the `update` job.
- Recipes carry a `[doc("...")]` directive and a `[group("...")]`. Commit messages are one line, `area: summary`. Every commit is signed. Do not rewrite pushed history.
- Public text follows the org voice guide in the `.github` repo, `docs/VOICE.md`.
