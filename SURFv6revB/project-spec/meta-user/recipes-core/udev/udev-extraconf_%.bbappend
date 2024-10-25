
do_install:append() {
	sed -i '$s|$|\n/dev/mmcblk1*|' ${D}${sysconfdir}/udev/mount.blacklist
}
