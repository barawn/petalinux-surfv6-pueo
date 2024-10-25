# petalinux SURFv6revB for PUEO

this is the onboard QSPI version

to create a BSP from this crap tar up the SURFv6revB directory into
something with a BSP extension, then you can create a petalinux
project with it.

Use the xsa in the hw directory here - it's based off of the
surf6_simple project which is literally just the zynqmp
PS configuration and nothing else.

you can also probably just use this directory as a petalinux
project, who the hell knows.