FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://platform-top.h file://bsp.cfg"

do_configure:append () {
	install ${WORKDIR}/platform-top.h ${S}/include/configs/
}

do_configure:append:microblaze () {
	if [ "${U_BOOT_AUTO_CONFIG}" = "1" ]; then
		install ${WORKDIR}/platform-auto.h ${S}/include/configs/
		install -d ${B}/source/board/xilinx/microblaze-generic/
		install ${WORKDIR}/config.mk ${B}/source/board/xilinx/microblaze-generic/
	fi
}
SRC_URI += "file://user_surf6.cfg \
            file://user_2024-10-09-16-32-00.cfg \
            file://user_2024-10-09-16-45-00.cfg \
            file://user_2024-10-09-17-19-00.cfg \
            file://user_2024-10-09-17-37-00.cfg \
            file://user_2024-10-09-17-41-00.cfg \
            file://user_2024-10-10-17-03-00.cfg \
            file://user_2024-10-10-17-15-00.cfg \
            "


