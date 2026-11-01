#!/bin/sh
set -eu

version=${1:?version required}
root=$(cd "$(dirname "$0")/../.." && pwd)
core="${root}/lib/core.sh"

if ! grep -q '^KATAZUKE_VERSION=' "${core}"; then
  printf 'no KATAZUKE_VERSION assignment found in %s\n' "${core}" >&2
  exit 1
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/katazuke-version-XXXXXX")
sed "s/^KATAZUKE_VERSION=\".*\"$/KATAZUKE_VERSION=\"${version}\"/" "${core}" >"${tmp}"
cat "${tmp}" >"${core}"
rm -f "${tmp}"

reported=$("${root}/bin/katazuke" --version)
printf 'version set to %s\n' "${reported}"
