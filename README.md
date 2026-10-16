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
- `release.yml` publishes a program on a `v*` tag, and is the only way the org does it. It runs the repo's CI, builds each platform in `.github/release.yaml`, bundles it the way the org dictates (`BINARY-TAG-ASSET.tar.gz`, or `.zip` for Windows, one folder holding the program and the `LICENSE`), writes `SHA256SUMS`, attests the archives, creates the GitHub release (notes are `docs/releases/TAG.md` if the repo has it, else the commits since the last tag, plus an install section), then writes a Homebrew cask, installs it on Homebrew on Linux and macOS and runs the program, and only then commits it to `baskingspot/homebrew-tap` as norm. See the header of the file for the caller. The caller needs `APP_PRIVATE_KEY` and `APP_CLIENT_ID`, which are org values scoped to selected repos: add a repo to both when it starts shipping a program. Another channel is another job after `publish`.
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

The jobs come from `.github/ci.yaml` in the calling repo, which is the way to configure a repo. Without that file, the `recipes`, `runners`, and `non-blocking` inputs below apply.

```yaml
# .github/ci.yaml
zig-cache: false # optional
jobs:
  - recipe: test
  - recipe: lint
  - recipe: check-target x86_64-linux
  - recipe: check-target x86-linux
    blocking: false # a stretch goal: it runs and shows, and never fails CI
  - recipe: test
    runners: [macos-26] # the default is [ubuntu-26.04]
    blocking: false
```

Each entry is a job. `recipe` is a `just` recipe with its arguments. A `runners` list makes one job per runner. `blocking: false` marks a stretch goal. A short first job reads the file and plans the matrix, which takes about 10 seconds. The caller then needs no `with:` block:

```yaml
jobs:
  ci:
    permissions:
      contents: read
    uses: baskingspot/gh-actions/.github/workflows/ci.yml@COMMIT # vX.Y.Z
    secrets:
      CACHIX_AUTH_TOKEN: ${{ secrets.CACHIX_AUTH_TOKEN }}
```

The inputs work as before when a repo has no `ci.yaml`.

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

To let some entries fail without failing the run, list them in `non-blocking`. It is for a target that is not first class: its job still runs and shows its result, but a failure leaves the run green.

```yaml
with:
  recipes: '["check x86_64-linux", "check wasm32-wasi"]'
  non-blocking: '["check wasm32-wasi"]'
```

A recipe may carry arguments: `'["check x86_64-linux", "check wasm32-wasi"]'` runs `just check x86_64-linux` and `just check wasm32-wasi` as two jobs. This is how one slow recipe, such as a cross-target compile gate, becomes a job per target.

Recipes and runners multiply: three recipes on two runners is six jobs. The default is `["ci"]`. The jobs are named `<recipe> (<runner>)`.

For a Zig repo, pass `zig-cache: true` to try the build cache. Measure it before you keep it. A build for the `native` CPU is keyed on the runner's CPU model, and GitHub's runners are a mix, so the cache hits only when a run lands on the same kind of machine. On stdx it helped `doc` and `test-release-fast` a little and did nothing for `test-release-safe`. The job restores `~/.cache/zig` and `.zig-cache` from the newest saved cache for that recipe and runner, and a run on the default branch saves a new one. A pull request reads the cache and never writes it. The cache is keyed by recipe, so each parallel job keeps its own.

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
