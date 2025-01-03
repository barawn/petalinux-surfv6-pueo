FILESEXTRAPATHS:prepend := "${THISDIR}/files:${SYSCONFIG_PATH}:"

SRC_URI:append = " file://config file://system-user.dtsi"

python () {
    if d.getVar("CONFIG_DISABLE"):
        d.setVarFlag("do_configure", "noexec", "1")
}

export PETALINUX
do_configure:append () {
    if [ -z "${CONFIG_DECOUPLING}" ]; then
	script="${PETALINUX}/etc/hsm/scripts/petalinux_hsm_bridge.tcl"
	data=${PETALINUX}/etc/hsm/data/
	eval xsct -sdx -nodisp ${script} -c ${WORKDIR}/config \
	-hdf ${DT_FILES_PATH}/hardware_description.${HDF_EXT} -repo ${S} \
	-data ${data} -sw ${DT_FILES_PATH} -o ${DT_FILES_PATH} -a "soc_mapping"
    fi
}

do_install:append() {
  for PP in *.dts.pp; do
      sed -e '/^#/d' < ${B}/${PP} > ${TOPDIR}/${PP}
  done
}
