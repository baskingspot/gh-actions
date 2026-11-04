#!/usr/bin/env bash
# Unit tests for setup-zig.sh. No network: the full install runs in
# .github/workflows/setup-zig.yml on every runner the org uses.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "${here}/setup-zig.sh"

fail() {
	printf 'not ok: %s\n' "$*" >&2
	exit 1
}

eq() {
	[ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"
}

eq "$(solve_version 0.16.0)" 0.16.0 'an explicit version'

eq "$(solve_filename 0.16.0 aarch64 linux)" zig-aarch64-linux-0.16.0.tar.xz 'the new tarball name'
eq "$(solve_filename 0.14.1 x86_64 linux)" zig-x86_64-linux-0.14.1.tar.xz 'the version the name changed'
eq "$(solve_filename 0.14.0 x86_64 linux)" zig-linux-x86_64-0.14.0.tar.xz 'the old tarball name'
eq "$(solve_filename 0.16.0 x86_64 windows)" zig-x86_64-windows-0.16.0.zip 'Windows is a zip'
eq "$(solve_filename 0.16.0 aarch64 macos)" zig-aarch64-macos-0.16.0.tar.xz 'macOS'

at_least 0.16.0 0.14.1 || fail '0.16.0 is at least 0.14.1'
at_least 0.14.1 0.14.1 || fail 'a version is at least itself'
at_least 0.14.0 0.14.1 && fail '0.14.0 is not 0.14.1'
at_least 0.17.0-dev.1+abcdef012 0.14.1 || fail 'a development build is newer'

signature_names $'timestamp:1776174236\tfile:zig-x.tar.xz\thashed' zig-x.tar.xz ||
	fail 'the file field'
signature_names $'timestamp:1\tfile:zig-x.tar.xz.evil\thashed' zig-x.tar.xz &&
	fail 'a longer name is not the name'
signature_names $'timestamp:1\tfile:other.tar.xz\thashed' zig-x.tar.xz &&
	fail 'another name is not the name'

eq "$(canonical_url zig-x86_64-linux-0.16.0.tar.xz 0.16.0)" \
	'https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz' 'a release'
eq "$(canonical_url zig-x86_64-linux-0.17.0-dev.1+abcdef012.tar.xz 0.17.0-dev.1+abcdef012)" \
	'https://ziglang.org/builds/zig-x86_64-linux-0.17.0-dev.1+abcdef012.tar.xz' 'a development build'

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
printf '.minimum_zig_version = "0.17.0",\n' >"${work}/build.zig.zon"
eq "$(cd "${work}" && solve_version '')" 0.17.0 'the version from build.zig.zon'

mkdir -p "${work}/empty"
if (cd "${work}/empty" && solve_version '' 2>/dev/null); then
	fail 'a missing version and build.zig.zon must fail'
fi

printf 'ok\n'
