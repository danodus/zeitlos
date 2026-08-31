#!/usr/bin/env bash
#
# Builds the SD card image by hand.
#
# NOTE: release/lib/mkfatimg.py builds the SAME image -- same mkfs.fat
# arguments, same file list, same fsck -- but populates it with mcopy
# instead of `mount -o loop`, so it needs no root. That matters here
# beyond convenience: a build run under sudo leaves root-owned .o files
# scattered through sw/, which then break every subsequent non-root
# build (the top-level Makefile's tftp-dist target has a comment about
# exactly this).
#
# Prefer:  release/zrelease build <version>
#
# This script is kept for the one-off case and as the readable
# reference for what goes on the card. If you change the file list
# here, change it in release/lib/mkfatimg.py too -- they are checked
# against each other by `release/zrelease check`.

set -euo pipefail

# mkfatimg.sh -- build the Zeitlos SD card image
#
# Produces images/zeitlos.img.gz: a FAT32 image holding the same file
# list the release images use (core apps live on flash, so only the
# supplemental apps, games/demos and docs go on the card), each stored
# by its bare name (<name>, no extension) so the running system finds
# it with `run <name>` / the dock. Apps that did not build (a
# deliberately removed one, an app whose sources are currently broken
# -- e.g. gpu3d when gpu3d.h/stl.h is missing) are simply skipped with
# a note.
#
# Uses mtools rather than mkfs.fat + loop mounts, so it needs no root
# and works identically on macOS and Linux:
#
#   macOS:      brew install mtools
#   Debian/Ub:  sudo apt install mtools
#
# Usage, from the repo root (after `make` so the apps exist, or just
# use the `sdimg` target -- ./sdimg builds them for you):
#
#   tools/mkfatimg.sh
#   gzip -dc images/zeitlos.img.gz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
#
# SIZE_MB (default 64) can be overridden:
#
#   ZTL_IMG_SIZE_MB=128 tools/mkfatimg.sh

IMAGE="images/zeitlos.img"
SIZE_MB="${ZTL_IMG_SIZE_MB:-64}"

for tool in mformat mcopy mmd mdir minfo gzip truncate; do
	command -v "$tool" >/dev/null || {
		echo "mkfatimg: '$tool' not found -- install mtools" \
			"(brew install mtools, or apt install mtools) and retry" >&2
		exit 1
	}
done

mkdir -p "$(dirname "$IMAGE")"
rm -f "$IMAGE" "$IMAGE.gz"

# A blank image the right size; block size 512, matching the card
# layout the SD driver (sw/os/fs/fatfs/sdmm.c) is brought up against.
truncate -s "${SIZE_MB}M" "$IMAGE"

# FAT32, one sector per cluster (smallest FAT32 allows; matches the
# original mkfs.fat -s 1 the release image used). total sectors
# = SIZE_MB*1024*1024/512. h/s are boot-sector bookkeeping values that
# FatFs does not look at -- any consistent pair works.
SECS=$((SIZE_MB * 1024 * 1024 / 512))
mformat -F -i "$IMAGE" -v ZEITLOS -T "$SECS" -h 128 -s 32 -c 1 ::

copied=0
skipped=0

copy_app() {
	if [ ! -f "$1" ]; then
		echo "mkfatimg: skipping $(basename "$1" .bin) (no $1 -- not built?)"
		skipped=$((skipped + 1))
		return
	fi
	mcopy -i "$IMAGE" "$1" "::$2"
	echo "mkfatimg: copied $2"
	copied=$((copied + 1))
}

# core apps exist on flash, so we exclude them; copy only the
# supplemental apps, games/demos, and misc files.

# make directory skeleton
mmd -i "$IMAGE" ::docs ::ark ::user

# supplemental apps
copy_app sw/apps/files/files.bin files
copy_app sw/apps/text/text.bin text
copy_app sw/apps/read/read.bin read
copy_app sw/apps/draw/draw.bin draw
copy_app sw/apps/info/info.bin info
copy_app sw/apps/calc/calc.bin calc
copy_app sw/apps/clock/clock.bin clock
copy_app sw/apps/settings/settings.bin settings
copy_app sw/apps/track/track.bin track

# games and demos
copy_app sw/apps/space3d/space3d.bin space3d
copy_app sw/apps/gamedemo/gamedemo.bin gamedemo
copy_app sw/apps/gpu3d/gpu3d.bin gpu3d

# misc
copy_app sw/apps/portdemo/portdemo.bin portdemo
mcopy -i "$IMAGE" docs/*.md ::docs/
mcopy -i "$IMAGE" sw/data/ark/*.md ::ark/

# Sanity: FAT geometry and the directory we ended up with.
minfo -i "$IMAGE" :: | sed -n '1,2p'
mdir -i "$IMAGE" ::

gzip "$IMAGE"
echo "mkfatimg: done -- $copied apps in $IMAGE.gz, $skipped skipped"