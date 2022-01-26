
BRANCH := baikalm
ARCH := arm64
ALTARCH := aarch64
EXTRA_CONFIGS ?= config-modules
CROSS_COMPILE := aarch64-linux-gnu-
DEFCONFIG := baikal_minimal_defconfig
ENABLE_INITRAMFS ?= auto
PATH_distcc := /usr/local/lib/distcc:/usr/bin:/bin:/sbin:/usr/sbin
PATH_ccache := /usr/local/lib/ccache:/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin
PATH_plain := /usr/bin:/bin:/sbin:/usr/sbin
SRCDIR := ../linux-$(BRANCH)
KBUILD_OUTPUT := /tmp/build/$(BRANCH)
KERNEL_STAGEDIR := /tmp/inst/$(BRANCH)
ISO_BASE_IMG := /srv/export/dist/altlinux/alt-p9-jeos-systemd-20210802-aarch64.iso
ISO_STAGE2 := altinst
ISO_REPLACE_PROPAGATOR := yes

COMMON_ENV := KBUILD_OUTPUT='$(KBUILD_OUTPUT)' KBUILD_BUILD_TIMESTAMP=yyyyyyyyyyyyyyyyyyyyyyyyyyyyy DISTCC_BACKOFF_PERIOD=0 DISTCC_FALLBACK=0
# Use distcc only (without ccache).
# Note: compilation nodes must be defined in ~/.distcc/hosts
ENV := env PATH='$(PATH_distcc)' $(COMMON_ENV)
# Use ccache with distcc
# Note: compilation nodes must be defined in ~/.distcc/hosts
# ENV := env PATH='$(PATH_ccache)' CCACHE_PREFIX=distcc $(COMMON_ENV)
# Use ccache, compile locally
# ENV := env PATH='$(PATH_ccache)' $(COMMON_ENV)
# Local compilation without ccache.
# KBUILD_BUILD_TIMESTAMP is set to avoid spurious recompilations.
# ENV := env PATH='$(PATH_plain)' $(COMMON_ENV)

.PHONY: all

all: install

.FORCE:


$(KBUILD_OUTPUT)/.config: $(SRCDIR)/arch/$(ARCH)/configs/$(DEFCONFIG)
	mkdir -p "$(dir $@)"
	$(ENV) $(MAKE) -C $(SRCDIR) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
	$(DEFCONFIG)


.PHONY: prepare

prepare: $(KBUILD_OUTPUT)/.config
	$(ENV) $(MAKE) -C $(SRCDIR) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
		prepare

.PHONY: menuconfig
menuconfig: $(KBUILD_OUTPUT)/.config
	$(ENV) $(MAKE) -C $(SRCDIR) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
	menuconfig

.PHONY: kernel
kernel: $(KBUILD_OUTPUT)/.config
	$(ENV) $(MAKE) -C $(SRCDIR) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
		all dtbs

.PHONY: install
install: kernel
	rm -rf $(KERNEL_STAGEDIR) 
	mkdir -p -m 755 $(KERNEL_STAGEDIR)/boot
	$(ENV) $(MAKE) -C $(SRCDIR) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
		INSTALL_PATH=$(KERNEL_STAGEDIR)/boot \
		INSTALL_MOD_PATH=$(KERNEL_STAGEDIR) \
		install modules_install dtbs_install
	depmod -b '$(KERNEL_STAGEDIR)' `cat $(KBUILD_OUTPUT)/include/config/kernel.release`

.PHONY: clean
clean:
	rm -rf $(KERNEL_STAGEDIR)
	$(ENV) $(MAKE) -C $(SRCDIR) \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
	clean

.PHONY: propagator

ifeq ($(strip $(ISO_REPLACE_PROPAGATOR)),)
propagator:

else
PROPAGATOR := ../propagator/init
propagator:
	$(ENV) \
		$(MAKE) -C "$(dir $(PROPAGATOR))" clean
	$(ENV) \
		$(MAKE) -C "$(dir $(PROPAGATOR))" \
		WITH_SHELL=1 WITH_CIFS=1 \
		ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE)
endif

.PHONY: iso
iso: install propagator
	$(ENV) \
		KBUILD_OUTPUT='$(KBUILD_OUTPUT)' \
		KERNEL_STAGEDIR='$(KERNEL_STAGEDIR)' \
		POST_HOOK=`pwd`/netinstall-deploy.sh \
		$(SHELL) iso-inject-kernel.sh \
		$(ISO_BASE_IMG) \
		$(ISO_STAGE2) \
		$(PROPAGATOR)


.PHONY: tarball
tarball: install
	kver=`cat $(KBUILD_OUTPUT)/include/config/kernel.release`; \
	if test -d $(KBUILD_OUTPUT)/$(ARCH)/boot/dts; then DTS_DIR="boot/dtbs/$$kver"; fi; \
	if grep -q -e 'CONFIG_MODULE_COMPRESS(_[^=]+)*[=]y' '$(KBUILD_OUTPUT)/.config'; then Z=''; else Z='z'; fi; \
	tarball="linux-$$kver-$(ARCH).tgz"; \
	if [ x"$Z" = x ]; then tarball="linux-$$kver-$(ARCH).tar"; fi; \
	fakeroot tar "c${Z}vf" $$tarball -C '$(KERNEL_STAGEDIR)' \
	boot/vmlinuz-$$kver \
	boot/config-$$kver \
	boot/System.map-$$kver \
	$$DTS_DIR \
	lib/modules/$$kver && echo $$tarball

.PHONY: deploy2hd
deploy2hd: tarball
	@kver=`cat $(KBUILD_OUTPUT)/include/config/kernel.release`; \
	if grep -q -e 'CONFIG_MODULE_COMPRESS(_[^=]+)*[=]y' '$(KBUILD_OUTPUT)/.config'; then Z=''; else Z='z'; fi; \
	tarball="linux-$$kver-$(ARCH).tgz"; \
	if [ x"$Z" = x ]; then tarball="linux-$$kver-$(ARCH).tar"; fi; \
	echo "ansible-playbook -i hosts -e KBUILD_OUTPUT='$(KBUILD_OUTPUT)' -e kernel_version=\'$$kver\' -e kernel_tarball=\'$$tarball' deploy2hd"; \
	ansible-playbook -i hosts \
		-e KBUILD_OUTPUT='$(KBUILD_OUTPUT)' \
		-e kernel_version="$$kver" \
		-e kernel_tarball="$$tarball" \
		deploy2hd.yml

.PHONY: printvars
printvars:
	echo 'BRANCH=$(BRANCH);'
	echo 'KBUILD_OUTPUT=$(KBUILD_OUTPUT);'
	echo 'KERNEL_STAGEDIR=$(KERNEL_STAGEDIR);'
	echo 'SRCDIR=$(SRCDIR);'
	echo 'ARCH=$(ARCH);'
