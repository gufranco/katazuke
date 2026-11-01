#!/bin/sh
sed -E \
  -e 's#/dev/r?disk[0-9]+s([0-9]+)#PART\1#g' \
  -e 's#/dev/loop[0-9]+p([0-9]+)#PART\1#g' \
  -e 's#/dev/r?disk[0-9]+#DEV#g' \
  -e 's#/dev/loop[0-9]+#DEV#g' \
  -e 's/(^| )(disk|loop)[0-9]+( |:|$)/\1DISK\3/g' \
  -e 's/[0-9]+\.[0-9] MiB/SIZE/g' \
  -e 's/, (DISK IMAGE|unnamed device)$/, NAME/'
