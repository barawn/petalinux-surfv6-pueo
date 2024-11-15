#!/bin/bash

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

# this is really "copy everything out of qspifs"
mount_pueofs() {
    # is /usr/local mounted (maybe we're being restarted)
    if mountpoint -q $PUEOFS ; then
	echo "${PUEOFS} is already mounted, skipping"
    else
	# the only thing we check is if the sqfs exists:
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
	    echo "Copying PUEO/python squashfs to tmp"
	    cp $PUEOSQUASHFS $PUEOTMPSQUASHFS
	    cp $PYTHONSQUASHFS $PYTHONTMPSQUASHFS
	    echo "Processing bitstream directory"
	    # this will take some time
	    if [ -e $PUEOBITDIR ] ; then
		uncompress_bitstreams ".gz" "gzip -d -k -c "
		uncompress_bitstreams ".bz2" "bzip2 -d -k -c "
		uncompress_bitstreams ".zst" "zstd -d --stdout "
	    fi
	    umount_qspifs
	fi
	# ok they should both exist now
	mount -t squashfs -o loop --source $PUEOTMPSQUASHFS $PUEOSQFSMNT
	MOUNTRET=$?
	if [ $MOUNTRET -eq 0 ] ; then
	    echo "${PUEOSQFSMNT} mounted OK from ${PUEOTMPSQUASHFS}"
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
if [ -f $PUEOBOOT ] ; then
    $PUEOBOOT &
    waitjob=$!
else
    sleep infinity &
    waitjob=$!
fi

wait
echo "Terminating"
umount_pueofs
