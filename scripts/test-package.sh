#!/usr/bin/env bash
# Runs package.sh over a fixture and checks the archives.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

mkdir -p "${work}/prefix/bin"
printf 'binary' >"${work}/prefix/bin/tool"
printf 'MIT License\n' >"${work}/LICENSE"

# A unix asset is a tarball with one folder holding the program and the license.
tgz=$(SOURCE_DATE_EPOCH=1000 "${here}/package.sh" tool v1.2.3 linux-x64 "${work}/prefix" "${work}/out" "${work}/LICENSE")
test "${tgz}" = "${work}/out/tool-v1.2.3-linux-x64.tar.gz"
listing=$(tar -tzf "${tgz}")
grep -qx 'tool-v1.2.3-linux-x64/' <<<"${listing}"
grep -qx 'tool-v1.2.3-linux-x64/tool' <<<"${listing}"
grep -qx 'tool-v1.2.3-linux-x64/LICENSE' <<<"${listing}"
test "$(tar -xOzf "${tgz}" tool-v1.2.3-linux-x64/LICENSE)" = "MIT License"
tar -xzf "${tgz}" -C "${work}"
test -x "${work}/tool-v1.2.3-linux-x64/tool"

# The same inputs make the same bytes.
again=$(SOURCE_DATE_EPOCH=1000 "${here}/package.sh" tool v1.2.3 linux-x64 "${work}/prefix" "${work}/out2" "${work}/LICENSE")
cmp "${tgz}" "${again}"

# A windows asset is a zip, and an exe keeps its name.
rm "${work}/prefix/bin/tool"
printf 'exe' >"${work}/prefix/bin/tool.exe"
printf 'symbols' >"${work}/prefix/bin/tool.pdb"
zipfile=$(SOURCE_DATE_EPOCH=1000 "${here}/package.sh" tool v1.2.3 windows-x64 "${work}/prefix" "${work}/out" "${work}/LICENSE")
test "${zipfile}" = "${work}/out/tool-v1.2.3-windows-x64.zip"
python3 - "${zipfile}" <<'PY'
import sys, zipfile
names = zipfile.ZipFile(sys.argv[1]).namelist()
assert "tool-v1.2.3-windows-x64/tool.exe" in names, names
assert "tool-v1.2.3-windows-x64/LICENSE" in names, names
assert not any(n.endswith(".pdb") for n in names), names
PY

# A relative output directory works too, as it does in CI (`dist`).
(cd "${work}" && "${here}/package.sh" tool v1.2.3 windows-x64 prefix rel-out LICENSE >/dev/null)
test -f "${work}/rel-out/tool-v1.2.3-windows-x64.zip"
(cd "${work}" && "${here}/package.sh" tool v1.2.3 linux-x64 prefix rel-out LICENSE >/dev/null)
test -f "${work}/rel-out/tool-v1.2.3-linux-x64.tar.gz"

# An empty prefix, or a missing license, stops the release.
if "${here}/package.sh" tool v1.2.3 linux-x64 "${work}/empty" "${work}/out" "${work}/LICENSE" 2>/dev/null; then
	echo "an empty prefix must fail" >&2
	exit 1
fi
if "${here}/package.sh" tool v1.2.3 linux-x64 "${work}/prefix" "${work}/out" "${work}/missing" 2>/dev/null; then
	echo "a missing license must fail" >&2
	exit 1
fi

echo "package: ok"
