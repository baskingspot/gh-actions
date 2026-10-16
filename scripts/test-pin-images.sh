#!/usr/bin/env bash
# Runs pin-images.sh over a fixture, with a resolver that needs no network.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

cat >"${work}/resolve" <<'RESOLVE'
#!/usr/bin/env bash
printf 'sha256:%s\n' "$(printf '%s' "$1" | sha256sum | cut -c1-64)"
RESOLVE
chmod +x "${work}/resolve"
export PIN_IMAGES_RESOLVE="${work}/resolve"

fixture="${work}/repo"
mkdir "${fixture}"
cat >"${fixture}/Dockerfile" <<'DOCKERFILE'
ARG BASE_IMAGE
FROM alpine:3 AS downloader
FROM --platform=linux/amd64 cgr.dev/chainguard/static:latest AS static
FROM scratch AS empty
FROM downloader AS again
FROM untagged AS noTag
FROM ${BASE_IMAGE} AS final
# alpine:3 appears here too, and is a comment
DOCKERFILE
cat >"${fixture}/docker-bake.hcl" <<'HCL'
target "alpine" {
  args = {
    BASE_IMAGE  = "alpine:3"
    ZIG_VERSION = "${ZIG_VERSION}"
    OTHER       = "alpine:3"
  }
}
HCL
cp "${fixture}/Dockerfile" "${work}/Dockerfile.before"

"${here}/pin-images.sh" "${fixture}" >"${work}/out1" 2>"${work}/err1"

alpine="alpine:3@$("${work}/resolve" alpine:3)"
static="cgr.dev/chainguard/static:latest@$("${work}/resolve" cgr.dev/chainguard/static:latest)"

# The tagged references are pinned, in both files.
grep -qxF "FROM ${alpine} AS downloader" "${fixture}/Dockerfile"
grep -qxF "FROM --platform=linux/amd64 ${static} AS static" "${fixture}/Dockerfile"
grep -qF "BASE_IMAGE  = \"${alpine}\"" "${fixture}/docker-bake.hcl"
# A variable that is not named *IMAGE is not touched.
grep -qF 'OTHER       = "alpine:3"' "${fixture}/docker-bake.hcl"
# scratch, a stage name, a variable, and an untagged reference stay as they were.
grep -qxF 'FROM scratch AS empty' "${fixture}/Dockerfile"
grep -qxF 'FROM downloader AS again' "${fixture}/Dockerfile"
grep -qxF 'FROM untagged AS noTag' "${fixture}/Dockerfile"
# shellcheck disable=SC2016
grep -qxF 'FROM ${BASE_IMAGE} AS final' "${fixture}/Dockerfile"
grep -qF 'has no tag, left alone' "${work}/err1"

# A second run changes nothing.
cp "${fixture}/Dockerfile" "${work}/Dockerfile.pinned"
"${here}/pin-images.sh" "${fixture}" >"${work}/out2" 2>/dev/null
cmp "${fixture}/Dockerfile" "${work}/Dockerfile.pinned"
grep -qF 'already at its current digest' "${work}/out2"

# A tag that moves is followed: the old digest is replaced, not appended.
cat >"${work}/resolve" <<'RESOLVE'
#!/usr/bin/env bash
printf 'sha256:%064d\n' 7
RESOLVE
"${here}/pin-images.sh" "${fixture}" >"${work}/out3" 2>/dev/null
grep -qxF "FROM alpine:3@sha256:$(printf '%064d' 7) AS downloader" "${fixture}/Dockerfile"
if grep -q 'sha256:[0-9a-f]*@sha256' "${fixture}/Dockerfile"; then
	echo "a digest was appended to a digest" >&2
	exit 1
fi

echo "pin-images: ok"
