FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append = " file://01_osu_hack_partial_readback_v10.patch \
 	           file://0001-enable-efuse-access.patch"

EXTERNALXSCTSRC=""
EXTERNALXSCTSRC_BUILD = ""

