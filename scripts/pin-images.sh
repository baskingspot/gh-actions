#!/usr/bin/env bash
# pin-images: pin the base images in a repo to their current digests.
#
#   pin-images.sh [DIR]     DIR defaults to the current directory
#
# It looks at two places in DIR, and only these:
#   - the FROM lines of every Dockerfile*. It skips scratch, a name with a
#     variable in it, and the name of an earlier stage.
#   - a line like  BASE_IMAGE = "alpine:3"  in every *.hcl file, any variable
#     whose name ends in IMAGE, for a docker bake file.
# A reference NAME:TAG becomes NAME:TAG@sha256:DIGEST. The tag stays so a
# reader sees what is pinned, and a later run follows the tag to its new
# digest. A reference with no tag is reported and left alone. The maintenance
# job runs this, and the repo's `just ci` gates the result.
#
# PIN_IMAGES_RESOLVE names a command that prints the digest of a reference.
# The test sets it. By default it asks `docker buildx imagetools inspect`.

set -euo pipefail

dir=${1:-.}

resolve() {
	if [ -n "${PIN_IMAGES_RESOLVE:-}" ]; then
		"${PIN_IMAGES_RESOLVE}" "$1"
	else
		docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' | jq -r .digest
	fi
}

# The image references a Dockerfile starts from, one per line.
dockerfile_refs() {
	awk '
    toupper($1) == "FROM" {
      i = 2
      while ($i ~ /^--/) i++
      ref = $i
      if (toupper($(i + 1)) == "AS") stage = $(i + 2); else stage = ""
      if (ref != "scratch" && ref !~ /\$/ && !(ref in stages)) print ref
      if (stage != "") stages[stage] = 1
    }
  ' "$1"
}

# The references an hcl file assigns to a variable whose name ends in IMAGE.
hcl_refs() {
	sed -nE 's/^[[:space:]]*[A-Za-z0-9_]*IMAGE[[:space:]]*=[[:space:]]*"([^"$]*)".*/\1/p' "$1"
}

changed=0

# Pins the references that EXTRACTOR prints for FILE, on the lines LINE matches.
# Nothing else in the file is touched, even if it holds the same text.
pin_in_file() {
	local file=$1 extractor=$2 line=$3 old base tag digest new
	while IFS= read -r old; do
		[ -n "${old}" ] || continue
		base=${old%%@*}
		tag=${base##*/}
		if [[ ${tag} != *:* ]]; then
			echo "${file}: ${old} has no tag, left alone" >&2
			continue
		fi
		digest=$(resolve "${base}")
		new="${base}@${digest}"
		if [ "${new}" = "${old}" ]; then
			continue
		fi
		OLD=${old} NEW=${new} LINE=${line} perl -pi -e 'if (/$ENV{LINE}/) { s/(?<![\w.\/:@-])\Q$ENV{OLD}\E(?![\w.\/:@-])/$ENV{NEW}/g }' "${file}"
		if [ "${old}" = "${base}" ]; then
			echo "${base}: pinned ${digest:0:19}"
		else
			echo "${base}: ${old##*@sha256:} -> ${digest#sha256:}" | cut -c1-200
		fi
		changed=1
	done < <("${extractor}" "${file}" | sort -u)
}

while IFS= read -r -d '' file; do
	pin_in_file "${file}" dockerfile_refs '(?i)^\s*FROM\b'
done < <(find "${dir}" -maxdepth 1 -type f -name 'Dockerfile*' -print0)

while IFS= read -r -d '' file; do
	pin_in_file "${file}" hcl_refs '^\s*\w*IMAGE\s*='
done < <(find "${dir}" -maxdepth 1 -type f -name '*.hcl' -print0)

if [ "${changed}" = 0 ]; then
	echo "Every base image is already at its current digest."
fi
