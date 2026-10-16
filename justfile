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

# Three days of trailing age for other people's actions, so a hijacked tag has
# time to be caught. Our own org's actions skip the age rule, so a release in
# baskingspot/gh-actions reaches every repo at once.
[doc("Pin every Action to its newest release. Outside baskingspot, at least three days old. Needs GITHUB_TOKEN")]
[group("actions")]
update:
    pinact run --update --min-age 3 --exclude '^baskingspot/'
    pinact run --update --include '^baskingspot/'
