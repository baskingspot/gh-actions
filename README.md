<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/static/logo-dark.svg">
    <img src="docs/static/logo.svg" alt="gh-actions" height="48">
  </picture>
</h1>

Shared GitHub Actions workflows for baskingspot, and the job that keeps every org repo current.

Every repo in the org has the same shape: a Nix flake, a justfile with a `ci` recipe, and workflows pinned by SHA. This repo holds the workflows they share and the job that keeps them up to date.

## Workflows

- `ci.yml` runs a repo's `just ci` recipe inside its Nix devshell. It installs Nix 2.35.3 with the Cachix installer and uses the `baskingspot` Cachix cache, and also pulls from `mattrobenolt`, where `ziglint` and `zigdoc` are prebuilt until they move under the org. A run on the default branch pushes new store paths to the cache. A pull request only reads from it. Pass `recipes` to run others.
- `deploy-docs.yml` builds a repo's docs site and deploys it to the repo's Cloudflare Worker, with the repo's `doc-deploy` recipe. The token is scoped to that Worker. See the header of the file for the caller.
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

To run the recipe on more than one runner, pass `runners`, a JSON array of labels. Each label is a separate job, and they run in parallel. All of these are free on a public repo:

```yaml
with:
  runners: '["ubuntu-26.04", "ubuntu-26.04-arm", "macos-26"]'
```

`ubuntu-26.04` is x86_64 Linux, `ubuntu-26.04-arm` is arm64 Linux, and `macos-26` is arm64 macOS. The default is `["ubuntu-26.04"]`. A repo only lists the runners where its recipe can pass: tools that exist only on Linux, like `perf`, fail on macOS.

To run more than one recipe, pass `recipes`, a JSON array. Each recipe is its own job, so tests, lint, and a docs build run at the same time. Each job installs Nix, which takes about 10 s with the Cachix cache, so split a recipe only when it is longer than that. `ci` stays the recipe a person runs locally to get everything:

```yaml
with:
  recipes: '["test", "lint", "doc"]'
```

Recipes and runners multiply: three recipes on two runners is six jobs. The default is `["ci"]`. The jobs are named `<recipe> (<runner>)`.

Pin the call by commit SHA. The maintenance job moves the pin when this repo changes.

## Keeping repos current

`maintain.yml` runs every Monday at 05:23 UTC. It lists the org's repos, skipping archived repos and forks. For each repo it runs up to three updates, one repo at a time:

- `flake.lock: update inputs`, for a repo that has a `flake.lock`. The commit message shows what moved.
- `ci: update pinned actions`, for a repo with workflows. It runs `pinact run --update`. Actions from other owners must be at least three days old. Our own `baskingspot/` actions skip that rule, so a release of a shared workflow reaches every repo at once.

- `docker: update pinned base images`, for a repo with a `Dockerfile` in its root. `scripts/pin-images.sh` pins every base image to a digest, as `alpine:3@sha256:...`. It reads the `FROM` lines of `Dockerfile*` and the `*IMAGE` variables of `*.hcl` bake files. The tag stays, and a later run follows the tag to its new digest. A reference with no tag is reported and left alone. A repo that builds and publishes its images rebuilds when the pin changes, because the commit touches the Dockerfile.

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

## How it's made

Built with LLM assistance. [How, in detail](https://github.com/baskingspot/.github/blob/main/docs/AI.md).

<a href="https://github.com/baskingspot"><img src="https://raw.githubusercontent.com/baskingspot/.github/main/brand/assets/badge.svg" alt="baskingspot" height="24"></a>
