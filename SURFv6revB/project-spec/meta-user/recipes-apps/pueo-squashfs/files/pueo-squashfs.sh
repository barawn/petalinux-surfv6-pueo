#!/bin/bash

# software override stuff
SFLD="SFLD"
SFOV="SFOV"
KEYFN="/sys/devices/platform/firmware:zynqmp-firmware/pggs0"
KEY=`cat $KEYFN | sed s/0x//g`
THE_KEY="deadbeef"

EEPROMCMD="dd if=/tmp/pueo/eeprom bs=4 skip=18 count=1 2>/dev/null"
OVCMD="dd if=/tmp/pueo/eeprom bs=1 skip=79 count=1 2>/dev/null"
S0CMD="dd if=/tmp/pueo/eeprom bs=1 skip=76 count=1 2>/dev/null"
S1CMD="dd if=/tmp/pueo/eeprom bs=1 skip=77 count=1 2>/dev/null"
S2CMD="dd if=/tmp/pueo/eeprom bs=1 skip=78 count=1 2>/dev/null"

# this is an overlay-ed filesystem merge
PUEOFS="/usr/local/"
PUEOSQUASHFS="/mnt/pueo.sqfs"
PYTHONSQUASHFS="/mnt/python.sqfs"
PUEOTMPSQUASHFS="/tmp/pueo/pueo.sqfs"
PYTHONTMPSQUASHFS="/tmp/pueo/python.sqfs"

# everything gets stored in /tmp/pueo.
# if you want to reread the qspifs, delete /tmp/pueo.
# if /tmp/pueo exists it is ASSUMED you don't want to
# reread!
# Note - even though /usr/local persists over restarts
# you can reset it back to default by just emptying
# the /tmp/pueo/pueo_sqfs_working directory.
PUEOTMPDIR="/tmp/pueo"
PUEOSQFSMNT="/tmp/pueo/pueo_sqfs_mnt"
PYTHONSQFSMNT="/tmp/pueo/python_sqfs_mnt"
PUEOUPPERMNT="/tmp/pueo/pueo_sqfs_working"
PUEOWORKMNT="/tmp/pueo/pueo_sqfs_ovdir"

PUEOSQFSNEXT="/tmp/pueo/next"

# bitstreams. these are stored compressed and uncompressed to /lib/firmware
# you can always try temporary bitstreams by just adding more to /lib/firmware
PUEOBITDIR="/mnt/bitstreams"
PUEOLIBBITDIR="/lib/firmware"
PUEOBOOT="/usr/local/boot.sh"

catch_term() {
    echo "termination signal caught"
    kill -TERM "$waitjob" 2>/dev/null
}

create_temporary_dirs() {
    # always safe
    if [ ! -e $PUEOTMPDIR ] ; then
       echo "Creating $PUEOTMPDIR and subdirectories."
       mkdir $PUEOTMPDIR
       mkdir $PYTHONSQFSMNT
       mkdir $PUEOSQFSMNT
       mkdir $PUEOUPPERMNT
       mkdir $PUEOWORKMNT
    else
       echo "Skipping creation of $PUEOTMPDIR and subdirs because it exists."
    fi
}

mount_qspifs() {
    # is it already mounted
    if [ ! `df | grep ubi0_0 | wc -l` -eq 0 ] ; then
	echo "qspifs is already mounted! abandoning..."
	# we do a hard exit here so we don't really have to check anymore
	# qspifs being mounted means someone's screwing with it
	exit 1
    fi
    echo "Mounting and attaching qspifs"
    ubiattach -m 2 /dev/ubi_ctrl
    # we do this read-only b/c we're just copying
    mount -o ro /dev/ubi0_0 /mnt
}

umount_qspifs() {
    echo "Unmounting and detaching qspifs"
    umount /mnt
    ubidetach -d 0 /dev/ubi_ctrl
}    

uncompress_bitstreams() {
    SFX=$1
    PROG=$2
    # search slots and main dir (for... whatever reason)
    for i in `ls ${PUEOBITDIR}/*${SFX} ${PUEOBITDIR}/[012]/*${SFX}`
    do
	NEWNAME="$(basename $i $SFX)"
	SLOTDIR="$(dirname $i)"
	SLOTNUM="$(basename $SLOTDIR)"
	DEST=${PUEOLIBBITDIR}/${NEWNAME}
	echo "Uncompressing $i to ${DEST}"
	# prog needs to decompress to stdout and keep original
	${PROG} $i > ${DEST}
	# check if it was in a slotdir
	if [ $SLOTDIR != $SLOTNUM ] ; then
	    LINKPATH=${PUEOLIBBITDIR}/${SLOTNUM}
	    echo "Linking ${LINKPATH} to ${DEST}"
	    ln -s ${DEST} ${LINKPATH}
	fi
    done
}

soft_slotname() {
    if [ $1 == "0" ] ; then
	echo "pueo.sqfs"
    else
	echo "pueo.sqfs.$1"
    fi    
}

soft_check() {
    if [ ! -f $1 ] ; then
	echo 1
    else
	unsquashfs -s $1 &> /dev/null
	echo $?
    fi    
}

find_soft_loadname() {
    # if /tmp/pueo/next exists this is not a boot, it's restart
    if [ -f "/tmp/pueo/next" ] ; then
	PUEOSQFS=$(readlink ${PUEOSQFSNEXT})
	if [ $(soft_check $PUEOSQFS) -ne 0 ] ; then
	    echo "Next software $PUEOSQFS is not valid, falling back"
	    PUEOSQFS="/tmp/pueo/pueo.sqfs"
	fi
    else
	OVLD=`$EEPROMCMD`
	if [ $OVLD == $SFOV ] ; then
	    # first check if we've reset
	    if [ $KEY == ${THE_KEY} ] ; then
		BOOTTYPE="reset"
		PUEOSQFS="/tmp/pueo/pueo.sqfs"
	    else		
		BOOTTYPE="power-on"
		OVSLT=`$OVCMD`
		PUEOSQFSNM=$(soft_slotname $OVSLT)
		PUEOSQFS="/tmp/pueo/$PUEOSQFSNM"
		if [ $(soft_check $PUEOSQFS) -ne 0 ] ; then
		    echo "$PUEOSQFS is not valid"
		    BOOTTYPE="power-on override failure"
		    PUEOSQFS="/tmp/pueo/pueo.sqfs"
		fi
		echo ${THE_KEY} > $KEYFN
	    fi
	    echo "Override $BOOTTYPE : using $PUEOSQFS"
	elif [ $OVLD == $SFLD ] ; then
	    S0=`$S0CMD`
	    S1=`$S1CMD`
	    S2=`$S2CMD`
	    echo "Soft load order $S0 $S1 $S2"
	    PUEOSQFSNM=$(soft_slotname $S0)
	    PUEOSQFS="/tmp/pueo/$PUEOSQFSNM"
	    if [ $(soft_check $PUEOSQFS) -ne 0 ] ; then
		echo "$PUEOSQFS is not valid, trying slot $S1"
		PUEOSQFSNM=$(soft_slotname $S1)
		PUEOSQFS="/tmp/pueo/$PUEOSQFSNM"
		if [ $(soft_check $PUEOSQFS) -ne 0 ] ; then
		    echo "$PUEOSQFS is not valid, trying slot $S2"
		    PUEOSQFSNM=$(soft_slotname $S2)
		    PUEOSQFS="/tmp/pueo/$PUEOSQFSNM"
		    if [ $(soft_check $PUEOSQFS) -ne 0 ] ; then
			echo "$PUEOSQFS is not valid, falling back"
			PUEOSQFS="/tmp/pueo/pueo.sqfs"
		    fi
		fi
	    fi
	else
	    PUEOSQFS="/tmp/pueo/pueo.sqfs"
	    echo "No override or load order: using $PUEOSQFS"
	fi
    fi    
}

# this is really "copy everything out of qspifs"
mount_pueofs() {
    # this happens if bmLiveRestart is called
    if mountpoint -q $PUEOFS ; then
	echo "${PUEOFS} is already mounted, skipping"
    else
	# the only thing we check is if the fallback sqfs exists:
	# if it does, we assume we're restarting, and don't
	# copy anything. Otherwise we copy everything.
	if [ ! -f $PUEOTMPSQUASHFS ] || [ ! -f $PYTHONTMPSQUASHFS ]; then
	    # remove them both
	    rm -rf $PUEOTMPSQUASHFS
	    rm -rf $PYTHONTMPSQUASHFS
	    echo "One of ${PUEOTMPSQUASHFS}/${PYTHONTMPSQUASHFS} was missing - assuming first time boot"
	    mount_qspifs
	    if [ ! -f $PUEOSQUASHFS ] ; then
		echo "No ${PUEOSQUASHFS} found! Aborting!"
		umount_qspifs
		exit 1
	    fi
	    if [ ! -f $PYTHONSQUASHFS ] ; then
		echo "No ${PYTHONSQUASHFS} found! Aborting!"
		umount_qspifs
		exit 1
	    fi
	    echo "Processing squashfses"
	    for sfs in `ls $SQUASHFSES` ; do
		destsfs="$PUEOTMPDIR/$sfs"
		echo "copying $sfs to $destsfs"
		cp $sfs $destsfs
	    done
	    echo "Processing bitstream directory"
	    # this will take some time
	    if [ -e $PUEOBITDIR ] ; then
		uncompress_bitstreams ".gz" "gzip -d -k -c "
		uncompress_bitstreams ".bz2" "bzip2 -d -k -c "
		uncompress_bitstreams ".zst" "zstd -d --stdout "
	    fi
	    umount_qspifs
	fi
	# figure out which soft to load
	find_soft_loadname
	# clear a next pointer if it exists
	rm -rf "/tmp/pueo/next"
	mount -t squashfs -o loop --source $PUEOSQFS $PUEOSQFSMNT
	MOUNTRET=$?
	if [ $MOUNTRET -eq 0 ] ; then
	    echo "${PUEOSQFSMNT} mounted OK from $PUEOSQFS"
	else
	    echo "PUEO sqfs mount failure: ${MOUNTRET}"
	    exit 1
	fi
	mount -t squashfs -o loop --source $PYTHONTMPSQUASHFS $PYTHONSQFSMNT
	MOUNTRET=$?
	if [ $MOUNTRET -eq 0 ] ; then
	    echo "${PYTHONSQFSMNT} mounted OK from ${PYTHONTMPSQUASHFS}"
	else
	    echo "Python sqfs mount failure: ${MOUNTRET}"
	    exit 1
	fi
	# and mount the overlay
	OVERLAYOPTIONS="lowerdir=${PYTHONSQFSMNT}:${PUEOSQFSMNT},upperdir=${PUEOUPPERMNT},workdir=${PUEOWORKMNT}"
	mount -t overlay --options=$OVERLAYOPTIONS overlay $PUEOFS
	MOUNTRET=$?
	if [ $MOUNTRET -eq 0 ] ; then
	    echo "${PUEOFS} mounted R/W as overlay FS."
	else
	    echo "Overlay mount failure: ${MOUNTRET}"
	    umount $PUEOTMPSQUASHFS
	    exit 1
	fi
	# and create the next pointer
	ln -s $PUEOSQFS $PUEOSQFSNEXT
    fi
}

umount_pueofs() {
    # lazy unmount, weirdly you get busy stuff or whatever occasionally
    umount -l $PUEOFS    
    umount -l $PUEOSQFSMNT
    umount -l $PYTHONSQFSMNT
    # give a moment to let things clean up
    sleep 0.25
}

cache_eeprom() {
    EEPROM="/sys/bus/i2c/devices/1-0050/eeprom"
    CACHE="/tmp/pueo/eeprom"
    if [ ! -f ${CACHE} ] ; then
	echo "Caching ${EEPROM} to ${CACHE}"
	cat $EEPROM > $CACHE
    fi
}

create_temporary_dirs
cache_eeprom
mount_pueofs

# catch termination
trap catch_term SIGTERM

# check if boot.sh exists in /usr/local
# If it does, it's the one that spawns 
# Otherwise we run sleep infinity
# Sleep infinity will return 0, so we
# always exit and restart
if [ -f $PUEOBOOT ] ; then
    $PUEOBOOT &
    waitjob=$!
else
    sleep infinity &
    waitjob=$!
fi

wait $waitjob
RETVAL=$?
# the magic exit code stuff here comes from using
# sleep infinity: you can zoink sleep infinity
# to test pueo-squashfs.

# killed with USR1: 138 (10)
if [ $RETVAL -eq 0 ] || [ $RETVAL -eq 138 ]; then
    echo "Unmounting, then restarting"
    umount_pueofs
    exit 0
fi
# killed with USR2: 140
if [ $RETVAL -eq 1 ] || [ $RETVAL -eq 140 ]; then
    echo "Restarting without unmounting"
    exit 0
fi
# killed with QUIT: 131
if [ $RETVAL -eq 2 ] || [ $RETVAL -eq 131 ]; then
    echo "Terminating without unmounting"
    exit 1
fi
# killed with TERM: 143
if [ $RETVAL -eq 3 ] || [ $RETVAL -eq 143 ]; then
    echo "Unmounting, then terminating"
    umount_pueofs
    exit 1
fi
# killed with INT: 130
if [$RETVAL -eq 4 ] || [ $RETVAL -eq 130 ]; then
    echo "Unmounting, cleaning up, then restarting"
    umount_pueofs
    sleep 1
    rm -rf ${PUEOTMPDIR}
    exit 0    
fi
# killed with ABRT: 136
if [$RETVAL -eq 5 ] || [ $RETVAL -eq 136 ]; then
    echo "Unmounting, cleaning up, then terminating"
    umount_pueofs
    sleep 1
    rm -rf ${PUEOTMPDIR}
    exit 1
fi
# killed with KILL: 137
if [ $RETVAL -eq 127 ] || [ $RETVAL -eq 137 ]; then
    echo "Terminating and rebooting!!"
    umount_pueofs
    sleep 1
    reboot
fi
