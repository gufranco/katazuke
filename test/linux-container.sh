#!/bin/sh
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
image="${KATAZUKE_TEST_IMAGE:-ubuntu:26.04}"

docker run --rm --privileged \
  -v "${repo}:/repo" \
  -w /repo \
  -e KATAZUKE_TEST_SHELLS="${KATAZUKE_TEST_SHELLS:-}" \
  -e KATAZUKE_TEST_RECORD="${KATAZUKE_TEST_RECORD:-}" \
  -e KATAZUKE_TEST_JOBS="${KATAZUKE_TEST_JOBS:-}" \
  "${image}" \
  sh -c '
    set -eu
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq --no-install-recommends \
      bats zsh dash util-linux mount eject udev sudo ca-certificates git fdisk \
      dosfstools exfatprogs e2fsprogs fatsort parallel procps python3 mandoc >/dev/null
    i=0
    while [ "$i" -lt 64 ]; do
      [ -e "/dev/loop$i" ] || mknod -m 660 "/dev/loop$i" b 7 "$i"
      i=$((i + 1))
    done
    exec "$@"
  ' sh "$@"
