# katazuke

Guidance for anyone, human or agent, changing katazuke. What katazuke is and how to use it lives in [README.md](README.md).

[FAMILY.md](FAMILY.md) holds everything katazuke shares with the rest of the kodougu family, and it is the same in every member. This file holds only what is exclusive to katazuke, under the same headings as the agent guide of every member. Read both before changing anything; a rule that would serve the other members goes into `FAMILY.md` instead of here.

## Layout

| Path | Holds |
|:-----|:------|
| [`bin/katazuke`](bin/katazuke) | The entry point: usage, options, the tidy flow and the check flow |
| [`lib/`](lib) | The modules. [`lib/state.sh`](lib/state.sh) declares every global, [`lib/disk.sh`](lib/disk.sh) finds and refuses disks, [`lib/tidy.sh`](lib/tidy.sh) holds the junk names, mounting, the read-only check and the sort |
| [`man/katazuke.1`](man/katazuke.1) | The man page |
| [`completions/`](completions) | bash, zsh and fish completions |
| [`test/`](test) | The `bats` suite, its helpers, the golden transcripts, the fake `sudo` and the Linux container script |
| [`scripts/`](scripts) | Coverage, the coverage gate, the Linux coverage run and the name check, which `make` runs |
| [`.github/scripts/`](.github/scripts) | The toolset helper and the release version stamp, which only CI and the release run |

## Names

- Globals carry `DISK_`; function-scoped variables carry a per-function `disk_` prefix, the same names kakikomi and kiyome use for their shared helpers.
- Settings come from `KATAZUKE_<NAME>`, such as `KATAZUKE_ORDER` or `KATAZUKE_JSON`; test switches are `KATAZUKE_INTERACTIVE`, `KATAZUKE_TEST_SHELLS`, `KATAZUKE_TEST_RECORD`, `KATAZUKE_TEST_GUM`, `KATAZUKE_TEST_GUM_LOG`, `KATAZUKE_TEST_GUM_ANSWERS` and `KATAZUKE_TEST_GUM_SPIN`.
- Output goes through `disk_info`, `disk_say`, `disk_success`, `disk_error` and `disk_warning`, which hand over to the `disk_ui_` helpers in [`lib/ui.sh`](lib/ui.sh) where gum draws.

## Behaviour

- katazuke has one job, so a bare `katazuke` on a terminal asks for the disk directly, listing only external disks that carry a FAT or exFAT volume.
- A run unmounts each volume, checks it read-only, mounts it, removes the junk, unmounts it, sorts it with fatsort, and ejects the disk at the end. A volume with filesystem errors stops the run before any change.
- A partition or volume stands for its whole disk, as the family rule says: `katazuke /dev/disk8s2` tidies every FAT and exFAT volume on `/dev/disk8` after one confirmation. The owner kept this on 2026-11-01 over narrowing to the named partition or asking which volumes to tidy.
- `check` mounts an unmounted volume read-only, lists its junk, and unmounts it again, so it never changes the disk.
- `--json` on a run reports the disk, whether it succeeded, the number of junk files removed, whether the disk was ejected, and each volume; on `check` it reports the disk, whether it is clean, and the junk on each volume.

## Domain rules

- Volume-level names, such as `System Volume Information` or `.Spotlight-V100`, are removed only at the top of a volume; per-file names, such as `._*` or `Thumbs.db`, in every folder. A folder below the top with a volume-level name is user content.
- `autorun.inf` and `DumpStack.log` are never removed: on a DOS or Windows game disk they can be real content.
- Cleaning while mounted, then unmounting, leaves a FAT32 disk image clean on macOS: nothing was written back at unmount (measured 2026-10-31). Writing `.fseventsd/no_log` adds four entries to the volume, so katazuke never writes it. Whether `mdutil -i off` leaves entries on a FAT volume is not yet measured, so katazuke leaves Spotlight settings alone.
- Natural order is fatsort's `natstrcmp`, which compares names byte by byte as C `char`. `char` is signed on Apple Silicon and unsigned on Linux arm64, so a name starting with an accented or non-Latin letter, such as `Ábaco` or `ゼルダ`, sorts before every A to Z name on macOS and after them on Linux arm64 (measured 2026-11-01). `--no-natural` runs fatsort's locale mode, which under `C.UTF-8` puts those names after every A to Z name on both systems and `Disc 10` before `Disc 2`. Under `en_US.UTF-8` on macOS that mode ignores accents but still sorts digit by digit, so stock fatsort offers no mode with both. The owner chose natural order with this behavior on 2026-11-01; patching fatsort was declined. The README states it.
- fatsort 1.6.5, which Ubuntu 26.04 ships, fails on exFAT volumes formatted by exfatprogs' `mkfs.exfat` with "parseExFATClusterChain: Unhandled return code!", while it sorts exFAT volumes macOS formats; fatsort 1.7.679 sorts both (measured 2026-11-01). katazuke cannot fix fatsort, so a failed exFAT sort under a fatsort older than 1.7 adds an error naming the fix, and `doctor` marks that fatsort `warn`.
- fatsort runs under `LC_ALL=C.UTF-8`, which macOS and Ubuntu both ship. Under `C` on Linux, fatsort's iconv turns every non-ASCII letter into `?` before comparing, so those names sorted before `A` and in an arbitrary order among themselves (measured 2026-11-01 on Linux arm64). Names on the disk are never changed either way.
- fatsort runs with `-c`, because the tool sets `LC_ALL=C`, which would otherwise make the order case-sensitive. Natural order adds `-n`; `--order` maps to `-o d`, `-o f` or `-o a`.
- A device the user can read and write, such as an image attached with `hdiutil`, is opened directly; any other goes through `sudo`. On Linux, `lsblk` reads filesystem types by probing the device when udev is absent, so those calls go through the same rule.
- Tests build real FAT12, FAT16, FAT32 and exFAT images, attached with `hdiutil` or `losetup`; the container runs privileged to reach loop devices.

## Release

- `KATAZUKE_VERSION` lives in [`lib/core.sh`](lib/core.sh).
- The tap's `Formula/katazuke.rb` depends on `fatsort` and `gum`.

## Gaps against FAMILY.md

- No README yet in English, Japanese, Simplified Chinese or Hong Kong Traditional Chinese (as of 2026-10-31).
- Not yet published: no GitHub repository, no formula in the tap, and katazuke is not yet in the member table of `FAMILY.md` (as of 2026-10-31).
