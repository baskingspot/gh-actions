<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/static/logo-dark.svg">
    <img src="docs/static/logo.svg" alt="gh-actions" height="48">
  </picture>
</h1>

Shared workflows for baskingspot, and the job that keeps every org repo current.

Every repo in the org has the same shape: a Nix flake, a justfile with a `ci` recipe, and workflows pinned by SHA. This repo holds the workflows they share and the job that keeps them up to date.

## Workflows

- `ci.yml` runs a repo's `just ci` recipe inside its Nix devshell, with the Determinate Nix installer and a cache. Pass `recipe` to run another recipe.
- `zizmor.yml` audits the repo's workflows and uploads the findings to the Security tab.

A repo calls them like this:

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:

permissions: {}

jobs:
  ci:
    permissions:
      contents: read
      id-token: write
    uses: baskingspot/gh-actions/.github/workflows/ci.yml@COMMIT # vX.Y.Z
```

Pin the call by commit SHA. The maintenance job moves the pin when this repo changes.

## Keeping repos current

`maintain.yml` runs every Monday at 05:23 UTC. It lists the org's repos, skipping archived repos and forks. For each repo it opens up to two pull requests:

- `flake.lock: update inputs`, for a repo that has a `flake.lock`. The body shows what moved.
- `ci: update pinned actions`, for a repo with workflows. It runs `pinact run --update`.

The pull requests come from the baskingspot GitHub App, so the commits are signed, and the repo's own CI runs on them. A repo needs nothing of its own to take part.

To run it now for one repo:

```sh
gh workflow run maintain.yml -f repo=NAME
```

The job reads the App's client ID from the org variable `APP_CLIENT_ID` and its private key from the secret `APP_PRIVATE_KEY`. Until the variable is set, the job skips. The key is limited to this repo, and every change to a workflow here needs review, because anyone who can change a workflow can read the key.

## Work on it

`nix develop` provides the tools, and `direnv allow` loads them. `just` lists the recipes, and `just ci` runs what CI runs.

## License

MIT. See `LICENSE`. The logo files in `docs/static/` are baskingspot marks and are not covered by it. See `docs/static/LICENSE`.
