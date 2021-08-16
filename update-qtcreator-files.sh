#!/bin/sh
set -e
MYDIR="${0%/*}"
cd "$MYDIR"
eval `make --silent -C "${MYDIR}" printvars`
fileslist=linux-${BRANCH}.files
mkdir -p -m755 "$KBUILD_OUTPUT"

list_sources () {
	local arches="$*"
	for arch in $arches; do
		git --git-dir="${SRCDIR}/.git" ls-files "arch/$arch/**.[chS]" | grep -v -E 'boot/dts/'
	done
	git --git-dir="${SRCDIR}/.git" ls-files '*.[chS]' | grep -v -E '^(arch)|(Documentation)|(tools)|(virt)'
}

cp_if_differs () {
	local src="$1"
	local dst="$2"
	if ! cmp -s "$src" "$dst"; then
		cp -a -f "$1" "$2"
	fi
}

list_sources arm arm64 | sort -u > "${fileslist}"
sed -re "s;^(.+)\$;${SRCDIR}/\\1;" -i "${fileslist}"
sed -re "s;@srcdir@;${SRCDIR};" \
	-e "s;@builddir@;${KBUILD_OUTPUT};" \
	linux-be-m1000.includes.in > linux-${BRANCH}.includes.tmp
mv linux-${BRANCH}.includes.tmp linux-${BRANCH}.includes
for p in cflags config creator; do
       cp_if_differs "linux-be-m1000.${p}" "linux-${BRANCH}.${p}"
done

make -j`nproc` -C "${MYDIR}" prepare
