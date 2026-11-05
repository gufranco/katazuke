#!/bin/sh
set -eu

: "${SCREENS_REPO:?}"
demo=/Users/Shared/demo
rm -rf "${demo}"
mkdir -p "${demo}/bin"
cp -f "${SCREENS_REPO}/test/shim/sudo" "${demo}/bin/sudo"
if [ -d /Volumes/EZFLASH ]; then
  hdiutil detach -quiet /Volumes/EZFLASH
fi
hdiutil create -quiet -size 64m -fs "MS-DOS FAT32" -volname EZFLASH -layout MBRSPUD "${demo}/ezflash.dmg"
listing=$(hdiutil attach "${demo}/ezflash.dmg")
device=$(printf '%s\n' "${listing}" | awk 'NR == 1 { print $1 }')
mkdir -p /Volumes/EZFLASH/GBA /Volumes/EZFLASH/.Trashes /Volumes/EZFLASH/.Spotlight-V100
for game in "Zelda - The Minish Cap" "Metroid Fusion" "Advance Wars" "Golden Sun" "Kirby"; do
  head -c 262144 /dev/urandom >"/Volumes/EZFLASH/GBA/${game}.gba"
  printf 'x' >"/Volumes/EZFLASH/GBA/._${game}.gba"
done
printf 'x' >/Volumes/EZFLASH/.DS_Store
printf 'x' >/Volumes/EZFLASH/GBA/.DS_Store
sync
printf 'DISK=%s\n' "${device##*/}" >"${demo}/demo.env"
