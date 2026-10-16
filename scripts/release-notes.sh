#!/usr/bin/env bash
# release-notes: write the notes for a release.
#
#   release-notes.sh TAG REPO DISTDIR
#
# The body is docs/releases/TAG.md when the repo has it, because a person wrote
# it for this release. Otherwise it is the commits since the previous tag,
# grouped by area: commits here are one line, `area: summary`, and a subject
# with no area goes under "other". Either way, an install section follows. It
# names the channels every release has, and the Windows zip if DISTDIR has one.

set -euo pipefail

tag=${1:?usage: release-notes.sh TAG REPO DISTDIR}
repo=${2:?repo}
dist=${3:?distdir}

if [ -f "docs/releases/${tag}.md" ]; then
	cat "docs/releases/${tag}.md"
else
	if previous=$(git describe --tags --abbrev=0 --match 'v*' "${tag}^" 2>/dev/null); then
		range="${previous}..${tag}"
		echo "Changes since ${previous}."
	else
		range="${tag}"
		echo "The first release."
	fi
	echo
	git log --no-merges --reverse --format='%s' "${range}" | awk '
    {
      if (match($0, /^[a-z0-9._-]+: /)) {
        area = substr($0, 1, RLENGTH - 2)
        text = substr($0, RLENGTH + 1)
      } else {
        area = "other"
        text = $0
      }
      if (!(area in seen)) {
        seen[area] = 1
        order[++count] = area
      }
      lines[area] = lines[area] "- " text "\n"
    }
    END {
      for (i = 1; i <= count; i++) {
        printf "## %s\n\n%s\n", order[i], lines[order[i]]
      }
    }
  '
fi

echo
echo "## Install"
echo
echo "- mise: \`mise use github:baskingspot/${repo}\`"
echo "- Homebrew: \`brew install --cask baskingspot/tap/${repo}\`"
echo "- Nix: \`nix run github:baskingspot/${repo}\`"
shopt -s nullglob
for zip in "${dist}"/*.zip; do
	echo "- Windows: unzip \`$(basename "${zip}")\` below and put the program on your \`PATH\`."
done
echo
echo "Every file is listed in \`SHA256SUMS\`, and attested by the org's release workflow. Check one with \`gh attestation verify FILE -R baskingspot/${repo} --signer-repo baskingspot/gh-actions\`."
