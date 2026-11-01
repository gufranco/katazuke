#!/bin/sh

LC_ALL=C
export LC_ALL

: "${DISK_LIB:=}"
: "${DISK_OS:=${KATAZUKE_OS:-}}"
: "${DISK_WIDTH:=80}"
: "${DISK_PROG:=katazuke}"
: "${DISK_VALUE_OPTIONS:=}"
: "${DISK_CLI_USED:=0}"
: "${DISK_TARGET:=}"
: "${DISK_PARTITIONS:=}"
: "${DISK_TMPDIR:=}"
: "${DISK_MOUNTED_HERE:=}"
: "${DISK_POINT:=}"
: "${DISK_REMOVED:=0}"
: "${DISK_EJECTED:=false}"
: "${DISK_JSON_PARTS:=}"
: "${DISK_FAILED:=0}"
