# baskingspot/gh-actions: the shared workflows and the job that keeps every
# org repo current. README.md says what lives here. AGENTS.md holds the
# working conventions.

[private]
default:
    @just --list

[doc("Check formatting, lint the workflows, and audit them with zizmor")]
[group("lint")]
lint:
    nix fmt -- --ci
    oxfmt --check README.md AGENTS.md
    actionlint
    zizmor .
    just --fmt --check

[doc("Format everything lint checks")]
[group("lint")]
fmt:
    nix fmt
    oxfmt README.md AGENTS.md
    just --fmt

[doc("Everything CI runs")]
[group("ci")]
ci: lint

[doc("Pin every Action to a commit SHA, leaving versions as they are. Needs GITHUB_TOKEN")]
[group("actions")]
pin:
    pinact run

# Three days of trailing age: a release has to survive that long before we
# pin to it, so a hijacked tag has time to be caught.
[doc("Pin every Action to the newest release at least three days old. Needs GITHUB_TOKEN")]
[group("actions")]
update:
    pinact run --update --min-age 3
