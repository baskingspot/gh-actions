<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/static/logo-dark.svg">
    <img src="docs/static/logo.svg" alt="gh-actions" height="48">
  </picture>
</h1>

Shared workflows for baskingspot, and the job that keeps every org repo current.

Every repo in the org has the same shape: a Nix flake, a justfile with a `ci` recipe, and workflows pinned by SHA. This repo holds the workflows they share and the job that keeps them up to date.

## Workflows

- `ci.yml` runs a repo's `just ci` recipe inside its Nix devshell. It installs Nix 2.35.3 with the Cachix installer and uses the `baskingspot` Cachix cache. A run on the default branch pushes new store paths to the cache. A pull request only reads from it. Pass `recipe` to run another recipe.
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
    uses: baskingspot/gh-actions/.github/workflows/ci.yml@COMMIT # vX.Y.Z
    secrets:
      CACHIX_AUTH_TOKEN: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

`CACHIX_AUTH_TOKEN` is an org secret, visible to every repo. A workflow that calls another one does not pass secrets on its own, so the call lists it. Without it the run still works, and only reads the cache.

Pin the call by commit SHA. The maintenance job moves the pin when this repo changes.

## Keeping repos current

`maintain.yml` runs every Monday at 05:23 UTC. It lists the org's repos, skipping archived repos and forks. For each repo it runs up to two updates, one repo at a time:

- `flake.lock: update inputs`, for a repo that has a `flake.lock`. The commit message shows what moved.
- `ci: update pinned actions`, for a repo with workflows. It runs `pinact run --update --min-age 3`, so it only pins to a release that is at least three days old.

A change has to pass the repo's own `just ci` first. Then it lands on the default branch as one commit, signed by the baskingspot GitHub App. There are no pull requests. If `just ci` fails, nothing is pushed and the run fails, so the failure shows in Actions. A repo needs nothing of its own to take part, except a `ci` recipe. If a repo protects its default branch, add the App as a bypass actor in the ruleset.

To run it now for one repo:

```sh
gh workflow run maintain.yml -f repo=NAME
```

The job reads the App's client ID from the org variable `APP_CLIENT_ID` and its private key from the secret `APP_PRIVATE_KEY`. Until the variable is set, the job skips. The key is limited to this repo, and every change to a workflow here needs review, because anyone who can change a workflow can read the key.

## Work on it

`nix develop` provides the tools, and `direnv allow` loads them. `just` lists the recipes, and `just ci` runs what CI runs.

## License

MIT. See `LICENSE`. The logo files in `docs/static/` are baskingspot marks and are not covered by it. See `docs/static/LICENSE`.
