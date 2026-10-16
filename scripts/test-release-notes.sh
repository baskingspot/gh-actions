#!/usr/bin/env bash
# Runs release-notes.sh over a throwaway git repo.
# The backticks in the single-quoted patterns are the literal text under test.
# shellcheck disable=SC2016
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
cd "${work}"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
g() { git -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
g init -q -b main .
g commit -q --allow-empty -m "core: first thing"
g tag v0.1.0
g commit -q --allow-empty -m "parser: reject a bare dot"
g commit -q --allow-empty -m "parser: accept a trailing newline"
g commit -q --allow-empty -m "a subject with no area"
g tag v0.2.0
mkdir dist

# No notes file: the commits since the previous tag, grouped by area.
notes=$("${here}/release-notes.sh" v0.2.0 tool dist)
grep -qx 'Changes since v0.1.0.' <<<"${notes}"
grep -qx '## parser' <<<"${notes}"
grep -qx -- '- reject a bare dot' <<<"${notes}"
grep -qx -- '- accept a trailing newline' <<<"${notes}"
grep -qx '## other' <<<"${notes}"
grep -qx -- '- a subject with no area' <<<"${notes}"
if grep -q 'first thing' <<<"${notes}"; then
	echo "a commit from before the previous tag leaked in" >&2
	exit 1
fi

# The install section names every channel, and no Windows line without a zip.
grep -qxF -- '- mise: `mise use github:baskingspot/tool`' <<<"${notes}"
grep -qxF -- '- Homebrew: `brew install --cask baskingspot/tap/tool`' <<<"${notes}"
grep -qxF -- '- Nix: `nix run github:baskingspot/tool`' <<<"${notes}"
if grep -q 'Windows' <<<"${notes}"; then
	echo "a Windows line appeared without a zip" >&2
	exit 1
fi
grep -qF 'gh attestation verify FILE -R baskingspot/tool' <<<"${notes}"

# The first release covers every commit.
first=$("${here}/release-notes.sh" v0.1.0 tool dist)
grep -qx 'The first release.' <<<"${first}"
grep -qx -- '- first thing' <<<"${first}"

# A Windows zip adds its line.
touch dist/tool-v0.2.0-windows-x64.zip
"${here}/release-notes.sh" v0.2.0 tool dist | grep -qF 'Windows: unzip `tool-v0.2.0-windows-x64.zip`'

# A written notes file replaces the generated body, and the install section stays.
mkdir -p docs/releases
printf '## What changed\n\nThe parser is stricter.\n' >docs/releases/v0.2.0.md
written=$("${here}/release-notes.sh" v0.2.0 tool dist)
grep -qx '## What changed' <<<"${written}"
if grep -q 'Changes since' <<<"${written}"; then
	echo "the generated body was used despite a notes file" >&2
	exit 1
fi
grep -q '^## Install' <<<"${written}"

echo "release-notes: ok"
