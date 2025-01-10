#!/bin/bash

# software override stuff
SFLD="SFLD"
SFOV="SFOV"
KEYFN="/sys/devices/platform/firmware:zynqmp-firmware/pggs0"
KEY=`cat $KEYFN | sed s/0x//g`
THE_KEY="deadbeef"

EEPROMCMD="dd if=/tmp/pueo/eeprom bs=4 skip=18 count=1"
OVCMD="dd if=/tmp/pueo/eeprom bs=1 skip=79 count=1"
S0CMD="dd if=/tmp/pueo/eeprom bs=1 skip=76 count=1"
S1CMD="dd if=/tmp/pueo/eeprom bs=1 skip=77 count=1"
S2CMD="dd if=/tmp/pueo/eeprom bs=1 skip=78 count=1"

SQUASHFSES="/mnt/*.sqfs"

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

# these are conveniently always the same
OVERLAYOPTIONS="lowerdir=${PYTHONSQFSMNT}:${PUEOSQFSMNT},upperdir=${PUEOUPPERMNT},workdir=${PUEOWORKMNT}"


# we only need a next pointer:
# we can find the currently loaded soft via losetup /dev/loop0
PUEOSQFSNEXT="/tmp/pueo/next"

# bitstreams. these are stored compressed and uncompressed to /lib/firmware
# you can always try temporary bitstreams by just adding more to /lib/firmware
PUEOBITDIR="/mnt/bitstreams"
PUEOLIBBITDIR="/lib/firmware"
PUEOBOOT="/usr/local/boot.sh"

SIGCODE=0

catch_term() {
    echo "termination signal caught"
    SIGCODE=143
    kill -TERM "$waitjob" 2>/dev/null
}

catch_usr1() {
    echo "user1 termination caught"
    SIGCODE=138
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

uncompress_and_copy_to_libfirmware() {
    BASEPATH=$1
    FN=$2
    BASE=$(basename $FN)
    GZBASE=$(basename $FN .gz)
    BZ2BASE=$(basename $FN .bz2)
    ZSTBASE=$(basename $FN .zst)
    XZBASE=$(basename $FN .xz)
    ZBASE=$(basename $FN .Z)

    SLOTDIR=$(dirname $FN)
    SLOTNUM=$(basename $SLOTDIR)    
    if [ $BASE != $GZBASE ] ; then
	PROG="gzip -d -k -c "
	DEST=${PUEOLIBBITDIR}/$GZBASE
    elif [ $BASE != $BZ2BASE ] ; then
	PROG="bzip2 -d -k -c "
	DEST=${PUEOLIBBITDIR}/$BZ2BASE
    elif [ $BASE != $ZSTBASE ] ; then
	PROG="zstd -d --stdout "
	DEST=${PUEOLIBBITDIR}/$ZSTBASE
    elif [ $BASE != $XZBASE ] ; then
	PROG="xzcat "
	DEST=${PUEOLIBBITDIR}/$XZBASE
    elif [ $BASE != $ZBASE ] ; then
	PROG="zcat "
	DEST=${PUEOLIBBITDIR}/$ZBASE
    else
	PROG="cat "
	DEST=${PUEOLIBBITDIR}/$BASE
    fi

    echo "Loading $FN to ${DEST}"
    ${PROG} $FN > ${DEST}
    if [ $SLOTDIR != $BASEPATH ] ; then
	LINKPATH=${PUEOLIBBITDIR}/${SLOTNUM}
	echo "Linking ${LINKPATH} to ${DEST}"
	if [ -f ${LINKPATH} ] ; then
	    rm ${LINKPATH}
	fi
	ln -s ${DEST} ${LINKPATH}
    fi
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
	OVLD=`$EEPROMCMD 2>/dev/null`
	if [ $OVLD == $SFOV ] ; then
	    # first check if we've reset
	    if [ $KEY == ${THE_KEY} ] ; then
		BOOTTYPE="reset"
		PUEOSQFS="/tmp/pueo/pueo.sqfs"
	    else
		BOOTTYPE="power-on"
		OVSLT=`$OVCMD 2>/dev/null`
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
	    S0=`$S0CMD 2>/dev/null`
	    S1=`$S1CMD 2>/dev/null`
	    S2=`$S2CMD 2>/dev/null`
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
	    echo "One of ${PUEOTMPSQUASHFS} or ${PYTHONTMPSQUASHFS} was missing - assuming first time boot"
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
		fn=$(basename $sfs)
		destsfs="$PUEOTMPDIR/$fn"
		echo "copying $sfs to $destsfs"
		cp $sfs $destsfs
	    done
	    echo "Processing bitstream directory"
	    # this will take some time
	    if [ -e $PUEOBITDIR ] ; then
		for f in `find $PUEOBITDIR -type f` ; do
		    uncompress_and_copy_to_libfirmware $PUEOBITDIR $f
		done
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
    # we don't need lazy umounts anymore,
    # we actively wait for things to close.
    umount $PUEOFS    
    umount $PUEOSQFSMNT
    umount $PYTHONSQFSMNT
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
trap catch_usr1 SIGUSR1

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

# wait up to a second for files to close
BUSY=yes
for i in `seq 1 100`; do
    NFLS=`lsof | grep $PUEOFS | wc -l`
    if [ $NFLS -eq 0 ] ; then
	echo "$PUEOFS became free after $i loops"
	BUSY=no
	break
    fi
    if [ $i -eq 100 ] ; then
	echo "Waited 100 loops: $PUEOFS still busy??"
	break
    fi
    sleep 0.01
done

# the magic exit code stuff here comes from using
# sleep infinity: you can zoink sleep infinity
# to test pueo-squashfs.

# CHANGED IN 0.3.0:
# We now ONLY support terminating without unmounting,
# the friggin' user can handle cleanup and stuff
# themselves. We also clean up the exit codes to map
# better.

# Handle if WE were terminated.
if [ $SIGCODE -eq 143 ]; then
    echo "SIGTERM received: doing unmount and restart"
    RETVAL=143
fi
if [ $SIGCODE -eq 138 ]; then
    echo "SIGUSR1 received: terminating without unmount"
    RETVAL=131
fi

# NOTE NOTE NOTE: if you mess around with crap in
# /usr/local, know what you're doing.
# Without a revert restart, anything you've changed
# in /usr/local will persist.

# NORMAL RESTART (0): killed with TERM: 143
# This is what we do on a normal systemctl stop or restart.
if [ $RETVAL -eq 0 ] || [ $RETVAL -eq 143 ]; then
    if [ $BUSY = no ] ; then
	echo "Unmounting, then restarting"
	umount_pueofs
    else
	echo "Unmount requested, but $PUEOFS is busy!"
    fi    
    exit 0
fi

# HOT RESTART (1): killed with USR2: 140
if [ $RETVAL -eq 1 ] || [ $RETVAL -eq 140 ]; then
    echo "Restarting without unmounting"
    exit 0
fi

# NORMAL REVERT RESTART (2): killed with INT: 130
if [ $RETVAL -eq 2 ] || [ $RETVAL -eq 130 ]; then
    if [ $BUSY = "no" ] ; then
	echo "Unmounting, reverting, then restarting"
	umount_pueofs
	rm -rf ${PUEOUPPERMNT}
	mkdir ${PUEOUPPERMNT}
    else
	echo "Revert requested, but $PUEOFS is busy!"
    fi    
    exit 0
fi

# HOT REVERT RESTART (3): killed with ABRT: 136
if [ $RETVAL -eq 3 ] || [ $RETVAL -eq 136 ]; then
    if [ $BUSY = "no" ] ; then
	echo "Reverting, then restarting without unmounting"
	# we only need to unmount the overlay, delete the upper mount,
	# and remount it.
	umount $PUEOFS
	rm -rf ${PUEOUPPERMNT}
	mkdir ${PUEOUPPERMNT}
	mount -t overlay --options=$OVERLAYOPTIONS overlay $PUEOFS
    else
	echo "Hot revert requested, but $PUEOFS is busy!"
    fi    
    exit 0
fi

# CLEANUP RESTART (4): killed with ALRM: 142
if [ $RETVAL -eq 4 ] || [ $RETVAL -eq 142 ]; then
    if [ $BUSY = "no" ] ; then
	echo "Unmounting, cleaning up, then restarting"
	umount_pueofs
	sleep 1
	rm -rf ${PUEOTMPDIR}
    else
	echo "Clean restart requested, but $PUEOFS is busy!"
    fi
    exit 0    
fi

# TERMINATE INSTEAD (126): killed with QUIT: 131
if [ $RETVAL -eq 126 ] || [ $RETVAL -eq 131 ]; then
    echo "Terminating without unmounting"
    exit 1
fi

# REBOOT (127): killed with KILL: 137
if [ $RETVAL -eq 127 ] || [ $RETVAL -eq 137 ]; then
    echo "Terminating and rebooting!!"
    if [ $BUSY = "no" ] ; then
	umount_pueofs
	sleep 1
    fi   
    reboot
    exit 1
fi

echo "Unknown exit code $RETVAL received!"
