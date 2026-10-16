#!/usr/bin/env bash
# package: bundle one built platform of a program into the archive the org
# dictates, so every program ships the same shape.
#
#   package.sh BINARY TAG ASSET SRCDIR OUTDIR [LICENSE]
#
# SRCDIR is the prefix the program's `just release-build` installed into, so
# the files are in SRCDIR/bin. The archive is named BINARY-TAG-ASSET and holds
# one folder of the same name, with the program's files and the LICENSE:
#
#   zigdoc-v1.2.3-linux-x64.tar.gz
#     zigdoc-v1.2.3-linux-x64/zigdoc
#     zigdoc-v1.2.3-linux-x64/LICENSE
#
# Debug symbols (*.pdb) are left out. A windows-* ASSET is a .zip, and every other ASSET is a .tar.gz. The archive
# is reproducible: file order, owners, and times are fixed. Set
# SOURCE_DATE_EPOCH to the release commit's time. Needs GNU tar, gzip, zip.

set -euo pipefail

binary=${1:?usage: package.sh BINARY TAG ASSET SRCDIR OUTDIR [LICENSE]}
tag=${2:?tag}
asset=${3:?asset}
src=${4:?srcdir}
out=${5:?outdir}
license=${6:-LICENSE}

name="${binary}-${tag}-${asset}"
epoch=${SOURCE_DATE_EPOCH:-0}

# Debug symbols (a Windows .pdb) are not shipped.
shopt -s nullglob
files=()
for file in "${src}"/bin/*; do
	case "${file}" in
	*.pdb) ;;
	*) files+=("${file}") ;;
	esac
done
if [ "${#files[@]}" -eq 0 ]; then
	echo "package: ${src}/bin has no files. release-build must install into the prefix it is given." >&2
	exit 1
fi
test -f "${license}" || {
	echo "package: no license file at ${license}" >&2
	exit 1
}

stage=$(mktemp -d)
trap 'rm -rf "${stage}"' EXIT
mkdir -p "${stage}/${name}" "${out}"
cp -- "${files[@]}" "${stage}/${name}/"
cp -- "${license}" "${stage}/${name}/LICENSE"
chmod 0755 "${stage}/${name}"
find "${stage}/${name}" -type f -exec chmod 0755 {} +
chmod 0644 "${stage}/${name}/LICENSE"
find "${stage}" -exec touch -d "@${epoch}" {} +

case "${asset}" in
windows-*)
	archive="${out}/${name}.zip"
	rm -f "${archive}"
	(cd "${stage}" && zip -X -r -q "${archive}" "${name}")
	;;
*)
	archive="${out}/${name}.tar.gz"
	tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@${epoch}" \
		-C "${stage}" -cf - "${name}" | gzip -n >"${archive}"
	;;
esac

echo "${archive}"
