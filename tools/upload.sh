#!/usr/bin/env bash
# Builds the .pdx and copies it straight onto a USB-connected Playdate's
# Games folder, instead of launching the Simulator (see simulate.sh for
# that). Uses the SDK's pdutil to reboot the device into data-disk mode
# (README.md in $PLAYDATE_SDK_PATH: "pdutil <serial port> datadisk"), then
# waits for it to reappear as a USB mass-storage disk and mounts it with
# udisksctl.
#
# Requires udisksctl/lsblk (util-linux/udisks2, standard on most Linux
# desktops). Set PLAYDATE_DEVICE to the device's serial port (e.g.
# /dev/ttyACM0) to skip autodetection, e.g. if more than one candidate
# device is present.
set -euo pipefail

./tools/build.sh

PDX_NAME="PesteringPoseidon.pdx"

if [ -n "${PLAYDATE_DEVICE:-}" ]; then
	device="$PLAYDATE_DEVICE"
else
	device=""
	for candidate in /dev/serial/by-id/*[Pp]laydate* /dev/ttyACM*; do
		[ -e "$candidate" ] && device="$candidate" && break
	done
	if [ -z "$device" ]; then
		echo "No Playdate found. Plug it in over USB, or set PLAYDATE_DEVICE" \
			"to its serial port (e.g. PLAYDATE_DEVICE=/dev/ttyACM0)." >&2
		exit 1
	fi
fi

echo "==> Rebooting Playdate at $device into data-disk mode"
"$PLAYDATE_SDK_PATH/bin/pdutil" "$device" datadisk

echo "==> Waiting for the data disk to reappear over USB"
disk=""
for _ in $(seq 1 30); do
	disk=$(lsblk -rno NAME,TYPE,MODEL | awk '$2 == "disk" && tolower($0) ~ /playdate/ {print $1; exit}')
	[ -n "$disk" ] && break
	sleep 1
done
if [ -z "$disk" ]; then
	echo "Timed out waiting for the Playdate's data disk to appear." >&2
	exit 1
fi

partition=$(lsblk -rno NAME,TYPE "/dev/$disk" | awk '$2 == "part" {print $1; exit}')
[ -z "$partition" ] && partition="$disk"

echo "==> Mounting /dev/$partition"
<<<<<<< HEAD
mount_output=$(udisksctl mount -b "/dev/$partition" --no-user-interaction)
mountpoint=$(echo "$mount_output" | sed -n 's/.* at \(.*\)\.$/\1/p')
if [ -z "$mountpoint" ]; then
	mountpoint=$(lsblk -rno MOUNTPOINT "/dev/$partition")
fi
if [ -z "$mountpoint" ]; then
	echo "Mounted /dev/$partition but couldn't determine its mountpoint." >&2
=======
# Desktop environments auto-mount removable disks on their own, which races
# our udisksctl call below -- lsblk sees the new partition (straight from
# the kernel) before udisks2 has finished registering it as a D-Bus object,
# so an immediate `udisksctl mount` can fail with "Error looking up object
# for device". Check for an existing (auto-)mount first, and only fall back
# to mounting it ourselves -- with retries to ride out that same race -- if
# nothing beat us to it.
mountpoint=""
for _ in $(seq 1 15); do
	mountpoint=$(lsblk -rno MOUNTPOINT "/dev/$partition")
	[ -n "$mountpoint" ] && break
	if mount_output=$(udisksctl mount -b "/dev/$partition" --no-user-interaction 2>/dev/null); then
		mountpoint=$(echo "$mount_output" | sed -n 's/.* at \(.*\)\.$/\1/p')
		[ -n "$mountpoint" ] && break
	fi
	sleep 1
done
if [ -z "$mountpoint" ]; then
	echo "Couldn't mount or find an existing mount for /dev/$partition." >&2
>>>>>>> 86ed15f (Add tools/upload.sh to push builds directly to a USB-connected Playdate)
	exit 1
fi

echo "==> Copying $PDX_NAME to $mountpoint/Games/"
mkdir -p "$mountpoint/Games"
rm -rf "${mountpoint:?}/Games/$PDX_NAME"
cp -r "$PDX_NAME" "$mountpoint/Games/"
sync

echo "==> Ejecting"
udisksctl unmount -b "/dev/$partition"
udisksctl power-off -b "/dev/$disk" 2>/dev/null || true

echo "Done. The Playdate should reboot back to normal mode; $PDX_NAME will be in its Games list."
