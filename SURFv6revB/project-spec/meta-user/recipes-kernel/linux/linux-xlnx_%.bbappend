FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://bsp.cfg"
KERNEL_FEATURES:append = " bsp.cfg"
SRC_URI += "file://surf_user.cfg \
            file://0001-backport-DCC-uart-serialization-option.patch \
            file://0001-add-partial-readback-support.patch \
            file://user_2024-10-04-14-15-00.cfg \
            file://user_2024-10-04-16-28-00.cfg \
            file://user_2024-10-04-17-01-00.cfg \
            file://user_2024-10-09-20-37-00.cfg \
            file://user_2024-10-11-18-38-00.cfg \
            file://user_2024-10-11-19-00-00.cfg \
            file://user_2024-10-15-20-29-00.cfg \
            file://user_2024-10-16-15-37-00.cfg \
            file://user_2024-10-24-19-44-00.cfg \
            file://user_2024-11-14-16-48-00.cfg \
            "

