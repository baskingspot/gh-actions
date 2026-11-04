#!/usr/bin/env bash
# setup-zig: install a Zig compiler for a workflow.
#
#   setup-zig.sh [VERSION]
#
# The tarball comes from zig.baskingspot.dev, the org's pull-through cache in
# front of the Zig community mirrors. The Zig Software Foundation's minisign
# signature is checked before anything is unpacked, and the signature's trusted
# comment must name the tarball that was asked for, so an upstream cannot swap
# in another build. The minisign binary is the upstream static release, pinned
# by sha256.
#
# VERSION may be empty, in which case build.zig.zon's minimum_zig_version is
# used. There is no `latest`: a CI run should name the compiler it tests.

set -euo pipefail

readonly ZSF_KEY='RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U'
readonly MIRROR='https://zig.baskingspot.dev'
readonly MINISIGN_VERSION='0.12'
readonly MINISIGN_BASE="https://github.com/jedisct1/minisign/releases/download/${MINISIGN_VERSION}"

die() {
	printf 'setup-zig: %s\n' "$*" >&2
	exit 1
}

# The version to install: the argument, else build.zig.zon.
solve_version() {
	local version=${1:-} found
	if [ -z "${version}" ]; then
		[ -f build.zig.zon ] || die 'no version given and no build.zig.zon'
		found=$(sed -n 's/^[[:space:]]*\.minimum_zig_version[[:space:]]*=[[:space:]]*"\([^"]*\)".*$/\1/p' build.zig.zon)
		version=${found%%$'\n'*}
	fi
	[ -n "${version}" ] || die 'build.zig.zon has no minimum_zig_version'
	printf '%s' "${version}"
}

# The machine and system as Zig names them: "aarch64 linux".
solve_platform() {
	local arch os
	case "$(uname -m)" in
	x86_64 | amd64) arch=x86_64 ;;
	aarch64 | arm64) arch=aarch64 ;;
	armv7* | armv6*) arch=arm ;;
	i386 | i686) arch=x86 ;;
	riscv64) arch=riscv64 ;;
	*) die "unsupported machine: $(uname -m)" ;;
	esac
	case "$(uname -s)" in
	Linux) os=linux ;;
	Darwin) os=macos ;;
	MINGW* | MSYS* | CYGWIN*) os=windows ;;
	*) die "unsupported system: $(uname -s)" ;;
	esac
	printf '%s %s\n' "${arch}" "${os}"
}

# True when the version is at least the wanted one, ignoring a pre-release
# suffix. awk because a shell cannot compare three dotted fields.
at_least() {
	awk -v have="$1" -v want="$2" 'BEGIN {
		split(have, h, /[.+-]/)
		split(want, w, ".")
		for (i = 1; i <= 3; i++) {
			if ((h[i] + 0) > (w[i] + 0)) exit 0
			if ((h[i] + 0) < (w[i] + 0)) exit 1
		}
		exit 0
	}'
}

# The tarball name. Zig moved from zig-<os>-<arch>-<version> to
# zig-<arch>-<os>-<version> in 0.14.1.
solve_filename() {
	local version=$1 arch=$2 os=$3 ext=tar.xz
	[ "${os}" = windows ] && ext=zip
	if at_least "${version}" 0.14.1; then
		printf 'zig-%s-%s-%s.%s' "${arch}" "${os}" "${version}" "${ext}"
	else
		printf 'zig-%s-%s-%s.%s' "${os}" "${arch}" "${version}" "${ext}"
	fi
}

# True when a minisign trusted comment names this file. The comment is
# tab-separated, and `file:` is one whole field, so a name that merely starts
# with the wanted one does not pass.
signature_names() {
	local comment=$1 filename=$2 field
	local -a fields
	IFS=$'\t' read -r -a fields <<<"${comment}"
	for field in "${fields[@]}"; do
		[ "${field}" = "file:${filename}" ] && return 0
	done
	return 1
}

# The minisign archive, its sha256, and the member to take: "URL SHA MEMBER".
solve_minisign() {
	local linux='9a599b48ba6eb7b1e80f12f36b94ceca7c00b7a5173c95c3efc88d9822957e73'
	local macos='89000b19535765f9cffc65a65d64a820f433ef6db8020667f7570e06bf6aac63'
	local windows='37b600344e20c19314b2e82813db2bfdcc408b77b876f7727889dbd46d539479'
	case "$1 $2" in
	'x86_64 linux') printf '%s %s %s' "${MINISIGN_BASE}/minisign-${MINISIGN_VERSION}-linux.tar.gz" "${linux}" 'minisign-linux/x86_64/minisign' ;;
	'aarch64 linux') printf '%s %s %s' "${MINISIGN_BASE}/minisign-${MINISIGN_VERSION}-linux.tar.gz" "${linux}" 'minisign-linux/aarch64/minisign' ;;
	'aarch64 macos') printf '%s %s %s' "${MINISIGN_BASE}/minisign-${MINISIGN_VERSION}-macos.zip" "${macos}" 'minisign' ;;
	'x86_64 windows') printf '%s %s %s' "${MINISIGN_BASE}/minisign-${MINISIGN_VERSION}-win64.zip" "${windows}" 'minisign-win64/x86_64/minisign.exe' ;;
	'aarch64 windows') printf '%s %s %s' "${MINISIGN_BASE}/minisign-${MINISIGN_VERSION}-win64.zip" "${windows}" 'minisign-win64/aarch64/minisign.exe' ;;
	*) die "the upstream minisign release has no build for $1 $2" ;;
	esac
}

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

unpack() { # archive destination
	case $1 in
	*.tar.gz)
		mkdir -p "$2"
		tar -xzf "$1" -C "$2"
		;;
	*.zip)
		if command -v unzip >/dev/null 2>&1; then
			unzip -q -o "$1" -d "$2"
		else
			# Windows: PowerShell. It needs Windows paths, and Git Bash's
			# cygpath is the only thing that knows them.
			local archive=$1 destination=$2
			if command -v cygpath >/dev/null 2>&1; then
				archive=$(cygpath -w "$1")
				destination=$(cygpath -w "$2")
			fi
			powershell.exe -NoProfile -Command "Expand-Archive -Force -LiteralPath '${archive}' -DestinationPath '${destination}'"
		fi
		;;
	*) die "cannot unpack $1" ;;
	esac
}

fetch() { # url destination
	curl -fsSL --retry 2 --retry-delay 2 --connect-timeout 20 --max-time 900 -o "$2" "$1"
}

# The canonical URL for a file, used only when the mirror cannot answer.
canonical_url() {
	case $1 in
	*-dev.*) printf 'https://ziglang.org/builds/%s' "$1" ;;
	*) printf 'https://ziglang.org/download/%s/%s' "$2" "$1" ;;
	esac
}

# The tarball, from the mirror and then, if it will not answer, the canonical
# site. A failure here is fatal: there is nothing else to try.
download() { # filename version destination
	if ! fetch "${MIRROR}/$1?source=github-baskingspot-setup-zig" "$3"; then
		fetch "$(canonical_url "$1" "$2")" "$3" || die "could not download $1"
	fi
}

main() {
	local version arch os filename dest work minisign_meta url sum member archive minisign out comment
	version=$(solve_version "${1:-}")
	read -r arch os < <(solve_platform)
	filename=$(solve_filename "${version}" "${arch}" "${os}")
	dest="${RUNNER_TOOL_CACHE:-${HOME}/.cache/baskingspot/zig}/${version}/${arch}-${os}"
	# Windows: Git Bash needs a POSIX path on PATH, and the runner needs a
	# Windows path in GITHUB_PATH. cygpath is the only thing that knows both.
	path_entry=${dest}
	if command -v cygpath >/dev/null 2>&1; then
		dest=$(cygpath -u "${dest}")
		path_entry=$(cygpath -w "${path_entry}")
	fi
	work=$(mktemp -d)
	# shellcheck disable=SC2064
	trap "rm -rf '${work}'" EXIT

	# The verifier first: a tarball that cannot be checked is not installed.
	minisign_meta=$(solve_minisign "${arch}" "${os}")
	read -r url sum member <<<"${minisign_meta}"
	archive="${work}/${url##*/}"
	fetch "${url}" "${archive}" || die 'could not download minisign'
	[ "$(sha256_of "${archive}")" = "${sum}" ] || die 'the minisign archive does not match its sha256'
	unpack "${archive}" "${work}/minisign"
	minisign="${work}/minisign/${member}"
	[ -f "${minisign}" ] || die "the minisign archive has no ${member}"
	chmod +x "${minisign}"

	download "${filename}" "${version}" "${work}/${filename}"
	download "${filename}.minisig" "${version}" "${work}/${filename}.minisig"

	out=$("${minisign}" -Vm "${work}/${filename}" -x "${work}/${filename}.minisig" -P "${ZSF_KEY}" 2>&1) ||
		die "the signature for ${filename} did not verify"
	comment=${out#*Trusted comment: }
	[ "${comment}" != "${out}" ] || die 'minisign printed no trusted comment'
	signature_names "${comment}" "${filename}" ||
		die "the signature names a file other than ${filename}"

	# A clean directory: a cached half-unpacked compiler from an older run must
	# not survive next to the new one.
	rm -rf "${dest}"
	mkdir -p "${dest}"
	case ${filename} in
	*.zip)
		unpack "${work}/${filename}" "${work}/unzipped"
		mv "${work}/unzipped/${filename%.zip}"/* "${dest}/" || die 'the archive has an unexpected layout'
		;;
	*) tar -xJf "${work}/${filename}" -C "${dest}" --strip-components=1 ;;
	esac

	# A Zig tarball holds the compiler at its root, not in bin/.
	if [ -n "${GITHUB_PATH:-}" ]; then
		printf '%s\n' "${path_entry}" >>"${GITHUB_PATH}"
	else
		export PATH="${dest}:${PATH}"
	fi
	PATH="${dest}:${PATH}" zig version
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	main "$@"
fi
