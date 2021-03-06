#!/bin/sh
set -e
MYDIR="${0%/*}"
MYNAME="${0##*/}"
export PATH="$HOME/work/squashfs-tools/squashfs-tools:$PATH"
IMG="${1:-/srv/export/dist/altlinux/slinux-live-9.1-aarch64.iso}"
STAGE2="${2:-live}"
PROPAGATOR="$3"

kver=`cat $KBUILD_OUTPUT/include/config/kernel.release`

sha1 () {
	local file="$1"
	local sha1=''
	sha1=`sha1sum "$file"`
	sha1="${sha1%% *}"
	echo "$sha1"
}

manifest () {
	local ret
	ret="$(for v in $@; do echo $v; done | sha1sum)"
	ret="${ret%% *}"
	echo "$ret"
}

IMG_SHA1=`sha1 $IMG`
PROPAGATOR_SHA1=''

set -x

if [ -n "$PROPAGATOR" ]; then
	if [ ! -r "$PROPAGATOR" ]; then
		"echo *** Error: $MYNAME: no such file $PROPAGATOR"
		exit 11
	fi
	PROPAGATOR_SHA1=`sha1 "$PROPAGATOR"`
fi

KERNEL_MANIFEST=`find $KERNEL_STAGEDIR -type f | xargs sha1sum | sort | sha1sum`
KERNEL_MANIFEST="${KERNEL_MANIFEST%% *}"
COMPLETE_MANIFEST=`manifest $IMG_SHA1 $KERNEL_MANIFEST $PROPAGATOR_SHA1`

OUT_IMG="${IMG##*/}"
OUT_IMG="${OUT_IMG%.iso}"
OUT_IMG="${OUT_IMG}-${COMPLETE_MANIFEST}.iso"
new_img="$HOME/.cache/altiso/${COMPLETE_MANIFEST}.iso"

if [ -f "$new_img" ]; then
	cp -alf "$new_img" "$OUT_IMG"
	echo "picked $new_img from cache"
	exit 0
fi

vmlinuz_new=`find $KERNEL_STAGEDIR/boot -type f -name "vmlinuz-$kver"`
if [ -z "$vmlinuz_new" ]; then
	echo "*** Error: remaster-iso: couldn't find vmlinuz in $KERNEL_STAGEDIR/boot" >&2
	exit 3
fi

INITRAMFS_PATH="$(xorriso -indev "stdio:${IMG}" -find / -type f -name 'full.cz' 2>/dev/null)"
INITRAMFS_PATH="${INITRAMFS_PATH#\'}"
INITRAMFS_PATH="${INITRAMFS_PATH%\'}"

if [ -z "$INITRAMFS_PATH" ]; then
	echo "*** Error: remaster-iso: couldn't find full.cz in $IMG" >&2
	exit 5
fi

KERNEL_PATH="$(xorriso -indev "stdio:${IMG}" -find / -type f -name 'vmlinuz' 2>/dev/null)"
KERNEL_PATH="${KERNEL_PATH#\'}"
KERNEL_PATH="${KERNEL_PATH%\'}"

if [ -z "$KERNEL_PATH" ]; then
	echo "*** Error: remaster-iso: couldn't find vmlinuz in $IMG" >&2
	exit 7
fi

full_cz_orig="/tmp/full.cz.orig.${IMG_SHA1}"
live_orig="/tmp/live.orig.${IMG_SHA1}"
rm -f "$full_cz_orig"
rm -f "$live_orig"
xorriso -dev stdio:$IMG -osirrox on -extract "$INITRAMFS_PATH" "$full_cz_orig"
xorriso -dev stdio:$IMG -osirrox on -extract "/${STAGE2}" "$live_orig"

SHA1=`sha1 "$live_orig"`
MANIFEST=`manifest $SHA1 $KERNEL_MANIFEST`

if [ -f "$HOME/.cache/altiso/${MANIFEST}.live" ]; then
	live="$HOME/.cache/altiso/${MANIFEST}.live"
else
	PARTIAL="$HOME/.cache/altiso/${SHA1}.partial"
	if [ ! -f "$PARTIAL" ]; then
		mkdir -p -m755 "$HOME/.cache/altiso"
		unsquashfs -pf "/tmp/${SHA1}.pseudo" -ex /lib \; "$live_orig"
		mksquashfs - "${PARTIAL}.tmp" -pf "/tmp/${SHA1}.pseudo" -comp xz
		mv "${PARTIAL}.tmp" "$PARTIAL"
		rm -f "/tmp/${SHA1}.pseudo"
	fi
	repack_dir="/tmp/lib.${SHA1}.d"
	rm -rf "$repack_dir"
	fake_db="/tmp/fake.${SHA1}.db"
	rm -f "$fake_db"
	fakeroot -s "$fake_db" unsquashfs -d "$repack_dir" "$live_orig" /lib
	fakeroot -i "$fake_db" -s "$fake_db" rsync -avcH --delete "${KERNEL_STAGEDIR}/lib/modules/" "${repack_dir}/lib/modules/"
	live="$HOME/.cache/altiso/${MANIFEST}.live"
	cp -a "$PARTIAL" "${live}.tmp"
	fakeroot -i "$fake_db" mksquashfs "$repack_dir" "${live}.tmp" -no-recovery
	mv "${live}.tmp" "$live"
	rm -rf "$repack_dir"
	rm -f "$fake_db"
fi

initramfs_sha1="`sha1 $full_cz_orig`"
FULL_CZ_MANIFEST=`manifest $initramfs_sha1 $KERNEL_MANIFEST $PROPAGATOR_SHA1`
echo "FULL_CZ_MANIFEST: ${FULL_CZ_MANIFEST}"

full_cz="$HOME/.cache/altiso/${FULL_CZ_MANIFEST}.full.cz"
if [ ! -f "$full_cz" ]; then
	propagator_initramfs="/tmp/propagator.${FULL_CZ_MANIFEST}"
	fake_db="/tmp/fake-${FULL_CZ_MANIFEST}.db"
	rm -f "$fake_db"
	rm -rf "$propagator_initramfs"
	mkdir -p -m755 "$propagator_initramfs"
	olddir=`pwd`
	cd "$propagator_initramfs"
	zcat "$full_cz_orig" | \
		while fakeroot -i "$fake_db" -s "$fake_db" \
			cpio -id --no-absolute-filenames; do :; done
	cd "$olddir"
	fakeroot -i "$fake_db" -s "$fake_db" rsync -avcH --delete "${KERNEL_STAGEDIR}/lib/modules/" "$propagator_initramfs/lib/modules/"
	if [ -n "$PROPAGATOR" ]; then
		fakeroot -i "$fake_db" -s "$fake_db" cp -a $PROPAGATOR "$propagator_initramfs"/sbin/init-bin
		fakeroot -i "$fake_db" -s "$fake_db" chown root:root "$propagator_initramfs"/sbin/init-bin
		fakeroot -i "$fake_db" -s "$fake_db" chmod 755 "$propagator_initramfs"/sbin/init-bin
	fi
	fakeroot -i "$fake_db" -- /bin/sh -c "cd $propagator_initramfs && find . | cpio -Hnewc --create" | pigz --stdout > "${full_cz}.tmp"
	mv "${full_cz}.tmp" "${full_cz}"
	rm -f "$fake_db"
fi

xorriso -indev stdio:$IMG -outdev stdio:"$new_img" \
	-update "$full_cz" "$INITRAMFS_PATH" \
	-update "$vmlinuz_new" "$KERNEL_PATH" \
	-update "$live" "/${STAGE2}" \
	-boot_image any replay

cp -alf "$new_img" "$OUT_IMG"
if [ -n "$POST_HOOK" ]; then
	env \
		KERNEL_PATH="$KERNEL_PATH" \
		INITRAMFS_PATH="$INITRAMFS_PATH" \
	$POST_HOOK "$OUT_IMG"
fi
