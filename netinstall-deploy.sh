#!/bin/sh
set -e
# expected environment
# KERNEL_PATH: path to initramfs in ISO, default: /boot/vmlinuz
# INITRAMFS_PATH: path to kernel in ISO, default: /boot/full.cz
# LIVE_SIZE: `live' squashfs image size, default: 8388608 bytes
# ALTINST_SIZE: `altinst' squashfs image size, default: 8388608 bytes

NETBOOT_DIR="$HOME/Public"
BASEURL="10.42.0.2"
ARCH=arm64
ALT_ARCH=aarch64


IMG="$1"
if [ -z "$IMG" ]; then
	echo "*** Error: netinstall-deploy: no image specified" >&2
fi

SHA256="`sha256sum $IMG`"
SHA256="${SHA256%% *}"

if [ -z "$KERNEL_PATH" ]; then
	KERNEL_PATH=/boot/vmlinuz
fi
if [ -z "$INITRAMFS_PATH" ]; then
	INITRAMFS_PATH=/boot/full.cz
fi

set -x
tftp_dir="${NETBOOT_DIR}/${IMG##*/}.d"
mkdir -p -m755 "${tftp_dir}${KERNEL_PATH%/*}"
mkdir -p -m755 "${tftp_dir}${INITRAMFS_PATH%/*}"

osirrox -indev stdio:"$IMG" \
	-extract "$KERNEL_PATH" "${tftp_dir}${KERNEL_PATH}" \
	-extract "$INITRAMFS_PATH" "${tftp_dir}${INITRAMFS_PATH}"

cp -al "$IMG" "$NETBOOT_DIR/$IMG"

cd ../netinstall

cat > tmp_alt_images.yml <<EOD
alt_images:
  - name: ${IMG##*/}
    url: http://`hostname`/dist/altlinux/${IMG##*/}
    checksum:
      sha256: $SHA256
    alt_arch: $ALT_ARCH
    grub_arch: $ARCH
    kernel: ${KERNEL_PATH:-/boot/vmlinuz}
    initrd: ${INITRAMFS_PATH:-/boot/full.cz}
    skip_iso_deploy: true
    live_size: ${LIVE_SIZE:-8388608}
    altinst_size: ${ALTINST_SIZE:-8388608}
    kernel_url: tftp://${BASEURL}/${IMG##*/}.d${KERNEL_PATH:-/boot/vmlinuz}
    initrd_url: tftp://${BASEURL}/${IMG##*/}.d${INITRAMFS_PATH:-/boot/full.cz}
    stage2_http_url: http://${BASEURL}/${IMG##*/}
EOD

exec ansible-playbook -i hosts -e@tmp_alt_images.yml site.yml
