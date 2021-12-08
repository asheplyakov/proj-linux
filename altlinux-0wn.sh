#!/bin/bash
set -e
HOSTNAME='asheplyakov-rpi4b'
SSH_PUB_KEY='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAEAQC4nppRTJ7Qa47L29r2H0lZHn6PaSTwribIYbC+rhn2Ar6toONVU2C+PBZCUAGzhep46Ojokl5fRGAPpA4Sj0MsOvu1o9qQP+EMuGDAuLQIF+c4YsGTVFUh/QrSXSwjyk2zL2PGiv9tS8MFLDqDNgR1VDv3MbCvlbnXQb8YGZRE7BQK9pkjCVwXCTobhOYPx6M8YO2NQRMKes6yZPrOwNj5cq5xfzA7bwYHjLlEPqXaMl1oFo8TEETmLta6/+j2FJo92xw66aOfRC+TMEyaQjj6M/1V5Q1wRvhGd54+O9dAyxNSpAtBdG48dTLs/gYn7F5XaGM6Yem7/LdMFm/kisayDFW2QGLrVWJ+Wv/RUaKWWteEwh+3ooRX2nC32I/1Cmzo+wPF6ERDw44jqJBlhXFoyb14y9n1YkxORbldbHJ7plQ3K/z1JEeAi6duj3zglMQvc03Dxd47GhMecJqUA1FBAVI2p4uaEx4vGQIor0GaeCEB+vP/w3E3HgOOgOgiCM8fB6XpHWUGMCGuAyamqqlAW4DAqRwzxzk7Q6a5CduYZaZZSpA+Bczog8HGIJ/seJH0HCh15pEB7lU6w/MlD9J4VJZl8v66x/cK+WQIjZS/THYPxuMXoB66I4hxz9usskkfWLq4siOokT86TalVBBi+LmGP5PocyA55nQD+ySF4g2xeRq78xeCd6sYCyQqvyifiirIiVQcCE804cHlyX997653JbYcYrsYShrSWfnbtsVzB+9VCkt6gAcqp604QnwF6N6BNTEg7ZQzALo//AHdDJq9iG40Af/TQWA/OjHcMk4fV5MhEurnkYxiFP4UHm8e/+oN5ILXB2udYokkW/A6dZY6sE/3H41IBbSYSIMLiI3FAEsJP3jii3/IELV7Ng4UgNXuFmpu4cLdFxLn/86VpC3rDmWYNKBVim3GG8IRaqqEHHM5eUh5xKpYr7SW17JbNrYRUL4mUnkO0p8bFgTpOsuVd2hfGgKmzC480E2ljwZqh3gcLCn0gtPbxcQ3h5+5HuRfAcEHV9rMa53q+h5qphqPXbbEeitf6zT2ntnn/RD/c5kM4iKJOYiw9+1CLh2kvtoLQ+I8jWJWxYmzz21LaVxNwkpi8moKPyVz+O5Q4GkDkmmtngJlTCci4P2EFEfPZJmjTAuj4OFyEDDNqHkADG16/6w7F9pooMGjQCpyUAzfG1VXFSOR+db1DwD41yHw4XbOy2c5mIkxZIFOma+OQBSQElAhfdz2DJe1ai7hfE//qRZKn1FiiSddOSwIDk3pmptjjMA/kZCxkl7KgXy9s7v5TUxO74gR9nHReIVTSUlyshgS1owmK00xoUiYH8RmKS4/aVxL8I/ODQhvw769X asheplyakov@asheplyakov-i5'
HTTP_PROXY="http://10.42.0.1:8080/"

if [ "$(stat -c %d:%i /)" != "$(stat -c %d:%i /proc/1/root/.)" ]; then
	echo 'altlinux-setup: running in chroot' >&2
	ACT_NOW=''
fi

copy_if_changed () {
	local src="$1"
	local dst="$2"
	local dst_dir="${2%/*}"
	local need_update='yes'
	if [ -e "$dst" ]; then
		if cmp -s "$src" "$dst"; then
			need_update='no'
		fi
	fi
	[ -d "$dst_dir" ] || mkdir -p -m755 "$dst_dir"
	if [ "$need_update" = 'yes' ]; then
		echo "[UPD] $dst" >&2
		cp -af "$src" "$dst"
	fi
}

ensure_authorized_keys_file () {
	local authorized_keys="$1"
	local dot_ssh_dir="${authorized_keys%/*}"

	if [ ! -d "$dot_ssh_dir" ]; then
		rm -f "$dot_ssh_dir"
		mkdir -p -m700 "$dot_ssh_dir"
	fi

	if [ ! -f "$authorized_keys" ]; then
		rm -f "$authorized_keys"
		touch "$authorized_keys"
		chmod 600 "$authorized_keys"
	fi
}

deploy_ssh_key () {
	local authorized_keys="$1"
	shift
	local key="$@"
	local fingerprint
	local current
	local need_update='yes'

	ensure_authorized_keys_file "$authorized_keys"

	fingerprint=`echo "$key" | ssh-keygen -f /dev/stdin -l | cut -d' ' -f2`
	while read line; do 
		current=`echo "$line" | ssh-keygen -f /dev/stdin -l 2>/dev/null | cut -d' ' -f2`
		if test "$current" = "$fingerprint"; then
			need_update='no'
			echo "altlinux-setup:deploy_ssh_key: "$fingerprint" is already in $authorized_keys" >&2
			break
		fi
	done < "$authorized_keys"

	if [ "$need_update" = 'yes' ]; then
		echo "altlinux-setup:deploy_ssh_key: UPD $authorized_keys $fingerprint" >&2
		echo "$key" >> "$authorized_keys"
	fi
}

configure_apt_proxy () {
	cat > /tmp/proxy.conf <<-EOF
	Acquire::http::proxy "${HTTP_PROXY}";
	EOF
	chmod 644 /tmp/proxy.conf
	copy_if_changed "/tmp/proxy.conf" "/etc/apt/apt.conf.d/proxy.conf"
}

enable_sshd () {
	systemctl enable ${ACT_NOW:---now} sshd
}

root_ssh_auth_setup () {
	deploy_ssh_key /root/.ssh/authorized_keys "$SSH_PUB_KEY"
}

apt_install_harder () {
	local pkg="$1"
	if ! rpm -q "$pkg" >/dev/null 2>&1; then
		echo "altlinux-setup:apt_install_harder: INSTALL $pkg" >&2
		if ! apt-get install -y "$pkg"; then
			echo "altlinux-setup:apt_install_harder: SOFTFAIL, updating APT cache" >&2
			apt-get update
			echo "altlinux-setup:apt_install_harder: retrying INSTALL $pkg" >&2
			if ! apt-get install -y "$pkg"; then
				echo "altlinux-setup:apt_install_harder: FAIL $pkg"
			fi
		fi
	else
		echo "altlinux-setup:apt_install_harder: $pkg already installed" >&2
	fi
}

ensure_systemd_resolved () {
	apt_install_harder systemd-networkd
	systemctl status systemd-resolved.service >/dev/null 2>&1 || if [ $? -eq 4 ]; then 
		echo 'altlinux-setup:ensure_systemd_resolved: systemctl daemon-reload' >&2
		systemctl daemon-reload
	else
		echo 'altlinux-setup:ensure_systemd_resolved: systemd-networkd unit already known' >&2
	fi

	systemctl enable ${ACT_NOW:---now} systemd-resolved.service
	ln -srf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
}

set_hostname () {
	if test "`hostname`" != "$HOSTNAME"; then
		echo "altlinux-setup:set_hostname: set-hostname $HOSTNAME" >&2
		hostnamectl set-hostname "$HOSTNAME"
	else
		echo "altlinux-setup:set_hostname: NOP, hostname is already $HOSTNAME" >&2
	fi
}


main () {
	root_ssh_auth_setup
	enable_sshd

	configure_apt_proxy

	set_hostname
	ensure_systemd_resolved
}

main
