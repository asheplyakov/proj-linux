#!/bin/sh
set -e
MYDIR="${0%/*}"
cd "$MYDIR"
fileslist=linux-be-m1000.files
eval `make --silent -C "${MYDIR}" printvars`
mkdir -p -m755 "$KBUILD_OUTPUT"

list_sources () {
	local arches="$*"
	for arch in $arches; do
		git --git-dir="${SRCDIR}/.git" ls-files "arch/$arch/**.[chS]" | grep -v -E 'boot/dts/'
	done
	git --git-dir="${SRCDIR}/.git" ls-files '*.[chS]' | grep -v -E '^(arch)|(Documentation)|(tools)|(virt)'
}

list_sources arm arm64 | sort -u > "${fileslist}"
sed -re "s;^(.+)\$;${SRCDIR}/\\1;" -i "${fileslist}"
sed -re "s;@srcdir@;${SRCDIR};" \
	-e "s;@builddir@;${KBUILD_OUTPUT};" \
	linux-be-m1000.includes.in > linux-be-m1000.includes.tmp
mv linux-be-m1000.includes.tmp linux-be-m1000.includes
