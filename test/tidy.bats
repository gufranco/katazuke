#!/usr/bin/env bats
# shellcheck disable=SC2016

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  disk_test_setup
}

teardown() {
  disk_test_teardown
}

interactive() {
  local input="$1"
  shift
  printf '%b' "${input}" | KATAZUKE_INTERACTIVE=1 disk_test_run "$@"
}

answering_path() {
  local answer="$1"
  local search_path="$2"
  shift 2
  printf '%s\n' "${answer}" | disk_test_run_path "${search_path}" "$@"
}

@test "a FAT32 disk loses its junk and keeps everything else" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_populate "${PART}" "GAME.TXT" "._GAME.TXT" ".DS_Store" "Saves/" "Saves/Thumbs.db" \
    "Saves/desktop.ini" "System Volume Information/" "Saves/Temporary Items/" "autorun.inf"

  # Act
  run disk_test_answering "${DEVICE##*/}" --no-eject "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Done. ${DEVICE} is tidy and still attached." ]]
  run disk_test_names "${PART}"
  [[ "${output}" == $'/GAME.TXT\n/Saves\n/Saves/Temporary Items\n/autorun.inf' ]]
}

@test "the default order is natural with folders first" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_populate "${PART}" "Disc 10.txt" "Disc 2.txt" "Disc 1.txt" "Saves/"

  # Act
  run disk_test_answering "${DEVICE##*/}" --no-eject "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  run disk_test_root_order "${PART}"
  [[ "${output}" == $'Saves\nDisc 1.txt\nDisc 2.txt\nDisc 10.txt' ]]
}

@test "accented and Japanese names survive the sort and plain names keep their order" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_populate "${PART}" "Zebra.txt" "Ábaco.txt" "Banana.txt" "ゼルダ.gba" "Abelha.txt"
  local order plain

  # Act
  run disk_test_answering "${DEVICE##*/}" --no-eject "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  order="$(disk_test_root_order "${PART}")"
  plain="$(LC_ALL=C grep -E '^[ -~]+$' <<<"${order}")"
  [[ "${plain}" == $'Abelha.txt\nBanana.txt\nZebra.txt' ]]
  [[ "${order}" == *"baco.txt"* ]]
  [[ "${order}" == *".gba"* ]]
  [[ "${order}" != *"?"* ]]
}

@test "--no-natural sorts digit by digit on a partitioned FAT16 disk" {
  # Arrange
  disk_test_disk fat16 mbr
  disk_test_populate "${PART}" "Disc 10.txt" "Disc 2.txt" "Disc 1.txt"

  # Act
  run disk_test_answering "${DEVICE##*/}" --no-natural --no-eject "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"Plan:   remove junk files, then sort folders first by name"* ]]
  run disk_test_root_order "${PART}"
  [[ "${output}" == $'Disc 1.txt\nDisc 10.txt\nDisc 2.txt' ]]
}

@test "--order files puts files before folders on FAT12" {
  # Arrange
  disk_test_disk fat12 none
  disk_test_populate "${PART}" "Bravo file.txt" "Folder/" "Alpha file.txt"

  # Act
  run disk_test_answering "${DEVICE##*/}" --order files --no-eject "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"then sort files first in natural order"* ]]
  run disk_test_root_order "${PART}"
  [[ "${output}" == $'Alpha file.txt\nBravo file.txt\nFolder' ]]
}

@test "KATAZUKE_ORDER=mixed sorts folders and files together on exFAT" {
  # Arrange
  disk_test_need_exfat_sort
  disk_test_disk exfat none
  disk_test_populate "${PART}" "c.txt" "B/" "a.txt"

  # Act
  KATAZUKE_ORDER=mixed KATAZUKE_EJECT=n run disk_test_answering "${DEVICE##*/}" "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"then sort folders and files together in natural order"* ]]
  run disk_test_root_order "${PART}"
  [[ "${output}" == $'a.txt\nB\nc.txt' ]]
}

@test "every FAT and exFAT volume on the disk is tidied and reported as JSON" {
  # Arrange
  disk_test_need_exfat_sort
  disk_test_two_volumes
  disk_test_populate "${PART}" "a.txt" "._a.txt"
  disk_test_populate "${PART2}" "b.txt" "Thumbs.db"
  local json

  # Act
  json="$(disk_test_answering "${DEVICE##*/}" --json --no-eject "${DEVICE}")"

  # Assert
  [[ "${json}" == "{\"disk\":\"${DEVICE}\",\"ok\":true,\"removed\":"*",\"ejected\":false,\"volumes\":[{\"device\":\"${PART}\",\"removed\":"*",\"sorted\":true},{\"device\":\"${PART2}\",\"removed\":"*",\"sorted\":true}]}" ]]
  run disk_test_names "${PART2}"
  [[ "${output}" == "/b.txt" ]]
}

@test "a real fatsort older than 1.7 names the fix for an exFAT volume it cannot sort" {
  # Arrange
  disk_test_need_exfat
  disk_test_exfat_sort_blocked || skip "this fatsort sorts every exFAT volume"
  disk_test_disk exfat none
  disk_test_populate "${PART}" "b.txt" "a.txt"

  # Act
  run disk_test_answering "${DEVICE##*/}" --no-eject "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"katazuke: fatsort could not sort ${PART}."* ]]
  [[ "${output}" == *"cannot sort every exFAT volume, such as one formatted by mkfs.exfat. fatsort 1.7 or later can." ]]
}

@test "an exFAT sort that fails under fatsort older than 1.7 names the fix" {
  # Arrange
  disk_test_disk exfat none
  disk_test_shim fatsort 'case "$1" in -v) echo "fatsort 1.6.5.640" ;; *) echo "parseExFATClusterChain: Unhandled return code!" >&2; exit 1 ;; esac'

  # Act
  run disk_test_call call_sort_report "${PART}" exfat

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"parseExFATClusterChain: Unhandled return code!"* ]]
  [[ "${output}" == *"katazuke: fatsort 1.6.5.640 cannot sort every exFAT volume, such as one formatted by mkfs.exfat. fatsort 1.7 or later can." ]]
}

@test "an exFAT sort that fails under fatsort 1.7 shows only fatsort's own words" {
  # Arrange
  disk_test_disk exfat none
  disk_test_shim fatsort 'case "$1" in -v) echo "fatsort 1.7.679" ;; *) echo "device busy" >&2; exit 1 ;; esac'

  # Act
  run disk_test_call call_sort_report "${PART}" exfat

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"device busy"* ]]
  [[ "${output}" != *"1.7 or later can"* ]]
}

@test "the summary names the disk, every volume and the plan" {
  # Arrange
  disk_test_two_volumes

  # Act
  run disk_test_answering stop "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  disk_test_matches_golden summary-two "${output}"
}

@test "a wrong name at the prompt changes nothing" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_populate "${PART}" "._GAME.TXT"

  # Act
  run disk_test_answering nope "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"katazuke: stopped: nothing was changed." ]]
  run disk_test_names "${PART}"
  [[ "${output}" == *"/._GAME.TXT"* ]]
}

@test "the disk is ejected at the end" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_shim diskutil 'case "$1" in eject) printf "ejected %s\n" "$2" >"'"${WORK}"'/ejected"; exit 0 ;; esac; exec "$REAL" "$@"'
  disk_test_shim eject 'printf "ejected %s\n" "$1" >"'"${WORK}"'/ejected"'

  local ejected

  # Act
  run disk_test_answering "${DEVICE##*/}" --natural --eject --json "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"\"ejected\":true"* ]]
  read -r ejected <"${WORK}/ejected"
  [[ "${ejected}" == "ejected ${DEVICE}" ]]
}

@test "a disk that will not eject is reported as tidy anyway" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_shim diskutil 'case "$1" in eject) exit 1 ;; esac; exec "$REAL" "$@"'
  disk_test_shim eject 'exit 1'

  # Act
  run disk_test_answering "${DEVICE##*/}" "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"katazuke: warning: ${DEVICE} did not eject. it is already tidy, so remove it once it is idle." ]]
}

@test "check lists the junk on a mounted volume and changes nothing" {
  # Arrange
  disk_test_disk fat32 none KTZ
  disk_test_populate "${PART}" "GAME.TXT" "Saves/" "Saves/Thumbs.db" "System Volume Information/"
  local point
  point="$(disk_test_mount "${PART}" rw)"

  # Act
  run disk_test_run check "${point}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"        /Saves/Thumbs.db"* ]]
  [[ "${output}" == *"        /System Volume Information"* ]]
  [[ "${output}" == *" junk files on ${DEVICE}. run katazuke ${DEVICE} to remove them." ]]
  [[ -e "${point}/Saves/Thumbs.db" ]]
}

@test "check reports a clean disk as JSON and leaves it unmounted" {
  # Arrange
  disk_test_disk fat16 mbr

  # Act
  run disk_test_run check --json "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "{\"disk\":\"${DEVICE}\",\"clean\":true,\"volumes\":[{\"device\":\"${PART}\",\"junk\":[]}]}" ]]
  run disk_test_call disk_mount_point "${PART}"
  [[ -z "${output}" ]]
}

@test "check says a clean volume has no junk files" {
  # Arrange
  disk_test_disk fat12 none

  # Act
  run disk_test_run check "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"        no junk files"* ]]
  [[ "${output}" == *"${DEVICE} is clean: no junk files found." ]]
}

@test "check lists junk as JSON strings" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_populate "${PART}" "Saves/Thumbs.db"

  # Act
  run disk_test_run check --json "${DEVICE}"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"\"clean\":false"* ]]
  [[ "${output}" == *"\"/Saves/Thumbs.db\""* ]]
}

@test "a volume with filesystem errors is left untouched" {
  # Arrange
  disk_test_disk fat16 none
  disk_test_populate "${PART}" "._GAME.TXT"
  disk_test_corrupt_fat "${PART}"

  # Act
  run disk_test_answering "${DEVICE##*/}" --no-eject "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"katazuke: stopped: ${PART} has filesystem errors, so it was not changed. repair it first."* ]]
  run disk_test_names "${PART}"
  [[ "${output}" == *"/._GAME.TXT"* ]]
}

@test "a missing checker stops the run before any change" {
  # Arrange
  disk_test_disk fat16 none
  local farm checker=fsck_msdos
  [[ "${KATAZUKE_TEST_OS}" == "Darwin" ]] || checker=fsck.vfat
  farm="$(disk_test_farm "${checker}")"

  # Act
  run answering_path "${DEVICE##*/}" "${farm}" --no-eject "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"katazuke: stopped: ${checker} is needed to check ${PART} before changing it. run 'katazuke doctor'." ]]
}

@test "a disk with no FAT or exFAT volume is refused" {
  # Arrange
  disk_test_disk other none

  # Act
  run disk_test_run check "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "katazuke: stopped: ${DEVICE} has no FAT or exFAT volume." ]]
}

@test "a volume that will not mount stops the run" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_shim diskutil 'case "$1" in mount) exit 1 ;; esac; exec "$REAL" "$@"'
  disk_test_shim mount '[ "$#" -eq 0 ] && exec "$REAL"; exit 1'

  # Act
  run disk_test_answering "${DEVICE##*/}" --no-eject "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"katazuke: could not mount ${PART}." ]]
}

@test "an exFAT volume is checked read-only before it is mounted" {
  # Arrange
  disk_test_disk exfat none
  disk_test_shim diskutil 'case "$1" in mount) exit 1 ;; esac; exec "$REAL" "$@"'
  disk_test_shim mount '[ "$#" -eq 0 ] && exec "$REAL"; exit 1'

  # Act
  run disk_test_answering "${DEVICE##*/}" --no-eject "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" != *"filesystem errors"* ]]
  [[ "${output}" == *"katazuke: could not mount ${PART}." ]]
}

@test "a volume that will not unmount stops the run" {
  # Arrange
  disk_test_disk fat32 none
  local point
  point="$(disk_test_mount "${PART}" rw)"
  disk_test_shim diskutil 'case "$1" in unmount) exit 1 ;; esac; exec "$REAL" "$@"'
  disk_test_shim umount 'exit 1'

  # Act
  run disk_test_answering "${DEVICE##*/}" --no-eject "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"katazuke: could not unmount ${PART}. close anything using ${point} and try again." ]]
}

@test "junk that cannot be removed stops the run" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_populate "${PART}" "._GAME.TXT"
  disk_test_shim rm 'exit 1'

  # Act
  run disk_test_answering "${DEVICE##*/}" --no-eject "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"katazuke: could not remove every junk file from "* ]]
}

@test "a fatsort failure is reported with what fatsort said" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_shim fatsort 'printf "fatsort: the disk is busy\n" >&2; exit 1'

  # Act
  run disk_test_answering "${DEVICE##*/}" --json --no-eject "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"katazuke: fatsort could not sort ${PART}."* ]]
  [[ "${output}" == *"fatsort: the disk is busy"* ]]
  [[ "${output}" == *"{\"disk\":\"${DEVICE}\",\"ok\":false,"* ]]
}

@test "check fails when a volume will not mount" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_shim diskutil 'case "$1" in mount) exit 1 ;; esac; exec "$REAL" "$@"'
  disk_test_shim mount '[ "$#" -eq 0 ] && exec "$REAL"; exit 1'

  # Act
  run disk_test_run check "${DEVICE}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "katazuke: could not mount ${PART}." ]]
}

@test "a bare katazuke on a terminal asks which disk to tidy" {
  # Arrange
  disk_test_disk fat32 none
  disk_test_populate "${PART}" "._GAME.TXT"

  # Act
  KATAZUKE_EJECT=n run interactive "${DEVICE##*/}\n${DEVICE##*/}\n"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *") ${DEVICE}"* ]]
  [[ "${output}" == *"Tidy which disk? Number or name: "* ]]
  [[ "${output}" == *"Done. ${DEVICE} is tidy and still attached." ]]
}

@test "the disk picker takes a number from its list" {
  # Arrange
  disk_test_disk fat32 none
  local listing number
  listing="$(interactive "" check 2>&1)" || true
  number="$(printf '%s\n' "${listing}" | awk -v dev="${DEVICE}" '$2 == dev { sub(/\)/, "", $1); print $1 }')"

  # Act
  run interactive "${number}\n" check

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"${DEVICE} is clean: no junk files found." ]]
}

@test "the disk picker refuses an answer that is not on its list" {
  # Arrange
  disk_test_disk fat32 none

  # Act
  run interactive "nope\n" check

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"katazuke: not a listed number or disk: nope" ]]
}

@test "the disk picker stops when stdin ends" {
  # Arrange
  disk_test_disk fat32 none

  # Act
  run interactive "" check

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"Tidy which disk? Number or name: " ]]
}

@test "the disk picker says when no disk qualifies" {
  # Arrange
  disk_test_shim diskutil 'case "$1" in list) exit 0 ;; esac; exec "$REAL" "$@"'
  disk_test_shim lsblk 'case "$*" in *NAME,TYPE,SIZE*) exit 0 ;; esac; exec "$REAL" "$@"'

  # Act
  run interactive ""

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "katazuke: no external or removable disk with a FAT or exFAT volume is attached." ]]
}
