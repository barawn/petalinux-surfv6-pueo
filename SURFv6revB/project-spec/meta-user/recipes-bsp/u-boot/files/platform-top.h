#include <configs/xilinx_zynqmp.h>

/* I have no idea how else to do this dumbass thing */
/* I'll figure out what else is needed later */
/* This is a massive hack-and-a-half: it's called scsi-init b/c
   petalinux does a preboot=run scsi_init, so we abuse that */
#define CONFIG_EXTRA_ENV_SETTINGS  \
  "mtdparts=nor0:1920k(boot),128k(bootscr),126M(qspifs)\0" \
  "scsi_init=setenv mm_ethaddr 0 \
    && i2c dev 1 \
    && i2c read 50 FA 6 $\{mm_ethaddr\} \
    && setexpr.b M0 *0x0 \
    && setexpr.b M1 *0x1 \
    && setexpr.b M2 *0x2 \
    && setexpr.b M3 *0x3 \
    && setexpr.b M4 *0x4 \
    && setexpr.b M5 *0x5 \
    && setenv -f ethaddr ${M0}:${M1}:${M2}:${M3}:${M4}:${M5} \
    && printenv ethaddr\0" \
  ""
