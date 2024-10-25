#include <configs/xilinx_zynqmp.h>

/* I have no idea how else to do this dumbass thing */
/* I'll figure out what else is needed later */

#define CONFIG_EXTRA_ENV_SETTINGS  \
  "mtdparts=nor0:1920k(boot),128k(bootscr),126M(qspifs)" \
  ""


