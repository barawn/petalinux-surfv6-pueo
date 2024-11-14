#
# This file is the pueo-squashfs recipe.
#

SUMMARY = "pueo-squashfs loader for /usr/local creation"
SECTION = "PETALINUX/apps"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://pueo-squashfs.sh \
	   file://pueo-squashfs-init \
           file://pueo-squashfs.service \
	"

RDEPENDS:${PN} += "bash"

S = "${WORKDIR}"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

inherit update-rc.d systemd

INITSCRIPT_NAME = "pueo-squashfs-init"
INITSCRIPT_PARAMS = "start 99 S ."

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "pueo-squashfs.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# we have to create /usr/local as well to allow the mountpoint to work.
do_install() {
	     if ${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', 'true', 'false', d)}; then
	        install -d ${D}${sysconfdir}/init.d/
		install -m 0755 ${WORKDIR}/pueo-squashfs-init ${D}${sysconfdir}/init.d
	     fi
	     
	     install -d ${D}/${bindir}
	     install -d ${D}/usr/local
	     install -m 0755 ${S}/pueo-squashfs.sh ${D}/${bindir}
	     install -d ${D}${systemd_system_unitdir}
	     install -m 0644 ${WORKDIR}/pueo-squashfs.service ${D}${systemd_system_unitdir}
}

FILES:${PN} += "${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', '${sysconfdir}/*', '', d)} /usr/local"
