#!/bin/bash
# Make an ISO image with newly compiled propagator
# Note:
# - the original image is not modified in any way
# Dependencies:
# - cpio
# - fakeroot
# - pigz
# - xorriso

set -e
IMG="$1"
PROPAGATOR="${2:-init}"
INITRAMFS_PATH=''

if [ -z "$IMG" ]; then
	echo "*** Error: implant-propagator: image must be specified" >&2
	exit 2
fi

if [ ! -e "$IMG" ]; then
	echo "*** Error: implant-propagator: no such file: $IMG" >&2
	exit 3
fi

if [ ! -e "$PROPAGATOR" ]; then
       echo "*** Error: implant-propagator: no such file: $PROPAGATOR" >&2
fi

sha1 () {
	local what="$1"
	local sum=`sha1sum "$what"`
	sum="${sum%% *}"
	echo "$sum"
}

manifest () {
	local sum=''
	sum="$(for elt in $@; do echo $elt; done | sha1sum)"
	sum="${sum%% *}"
	echo "$sum"
}

set -x

IMG_SHA1=`sha1 "$IMG"`
PROPAGATOR_SHA1=`sha1 "$PROPAGATOR"`
SCRIPT_SHA1=`sha1 $0`
MANIFEST=`manifest $IMG_SHA1 $PROPAGATOR_SHA1` # $SCRIPT_SHA1
OUT_IMG="${IMG##*/}"
OUT_IMG="${OUT_IMG%.iso}"
OUT_IMG="${OUT_IMG}-${MANIFEST}.iso"

set -x

cached_iso="$HOME/.cache/altiso/${MANIFEST}.iso"

if [ -f "$cached_iso" ]; then
	cp -al "$cached_iso" "$OUT_IMG"
	echo "picked ISO ${MANIFEST}.iso from cache"
	exit 0
fi

INITRAMFS_PATH="$(xorriso -indev "stdio:${IMG}" -find / -type f -name 'full.cz' 2>/dev/null |head -n1)"
INITRAMFS_PATH="${INITRAMFS_PATH#\'}"
INITRAMFS_PATH="${INITRAMFS_PATH%\'}"

if [ -z "$INITRAMFS_PATH" ]; then
	echo "*** Error: implant-propagator: couldn't find full.cz in $IMG" >&2
	exit 5
fi

orig_initramfs="/tmp/${IMG_SHA1}.full.cz.org"
extract_dir="/tmp/${IMG_SHA1}.propagator-initramfs"
fake_db="/tmp/${IMG_SHA1}.fake.db"
rm -f "$fake_db"
rm -f "$orig_initramfs"
rm -rf "$extract_dir"
touch "$fake_db"
mkdir -p -m755 "$extract_dir"

xorriso -indev stdio:"$IMG" -osirrox on -extract "$INITRAMFS_PATH" "$orig_initramfs"

INITRAMFS_SHA1="`sha1 $orig_initramfs`"
INITRAMFS_MANIFEST="`manifest $INITRAMFS_SHA1 $PROPAGATOR_SHA1`"

cached_initramfs="$HOME/.cache/altiso/${INITRAMFS_MANIFEST}.full.cz"
new_initramfs="${INITRAMFS_MANIFEST}.full.cz"
if [ -f "$cached_initramfs" ]; then
	cp -al "$cached_initramfs" "$new_initramfs"
	echo "picked initramfs ${INITRAMFS_MANIFEST} from cache"
else
	olddir="`pwd`"
	cd "$extract_dir"

	# XXX: tell cpio to extract files unconditionally (-u)
	# so the correct modules.dep.bin gets copied
	zcat "$orig_initramfs" | \
		while fakeroot -i "$fake_db" -s "$fake_db" \
			cpio -id -u --no-absolute-filenames; do :; done

	cd "$olddir"
	fakeroot -i "$fake_db" -s "$fake_db" -- /bin/sh -c "cp -a $PROPAGATOR "$extract_dir"/sbin/init-bin"
	fakeroot -i "$fake_db" -s "$fake_db" -- /bin/sh -c "chown root:root "$extract_dir"/sbin/init-bin"
	fakeroot -i "$fake_db" -s "$fake_db" -- /bin/sh -c "chmod 755 "$extract_dir"/sbin/init-bin"
	fakeroot -i "$fake_db" -- /bin/sh -c "cd "$extract_dir" && find . | cpio -Hnewc --create" | \
		pigz --stdout > "${new_initramfs}.tmp"
	cp -al "${new_initramfs}.tmp" "$cached_initramfs"
	mv "${new_initramfs}.tmp" "$new_initramfs"
	if [ -z "$KEEP_TEMPS" ]; then
		rm -f "$fake_db"
		rm -f "$orig_initramfs"
		rm -rf "$extract_dir"
	fi
fi

xorriso -indev stdio:"$IMG" -outdev stdio:"${OUT_IMG}.tmp" \
	-update "$new_initramfs" "$INITRAMFS_PATH" \
	-boot_image any replay

cp -al "${OUT_IMG}.tmp" "$cached_iso"
mv "${OUT_IMG}.tmp" "$OUT_IMG"
echo "${IMG_OUT}"
