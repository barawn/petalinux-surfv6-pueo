FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://0001-PUEO-journald.conf.patch \
            file://0001-disable-nonexistent-vt.patch \
            "

