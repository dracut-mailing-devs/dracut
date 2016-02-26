#!/bin/bash

# called by dracut
check() {
    return 255
}

# called by dracut
depends() {
    return 0
}

# called by dracut
install() {
    inst_hook cmdline   00 "$moddir/watchdog.sh"
    inst_hook cmdline   50 "$moddir/watchdog.sh"
    inst_hook pre-trigger 00 "$moddir/watchdog.sh"
    inst_hook initqueue 00 "$moddir/watchdog.sh"
    inst_hook mount     00 "$moddir/watchdog.sh"
    inst_hook mount     50 "$moddir/watchdog.sh"
    inst_hook mount     99 "$moddir/watchdog.sh"
    inst_hook pre-pivot 00 "$moddir/watchdog.sh"
    inst_hook pre-pivot 99 "$moddir/watchdog.sh"
    inst_hook cleanup   00 "$moddir/watchdog.sh"
    inst_hook cleanup   99 "$moddir/watchdog.sh"
    inst_hook emergency 02 "$moddir/watchdog-stop.sh"
    inst_multiple -o wdctl
}

installkernel() {
    if [[ $hostonly ]] && [[ $nowdt != "yes" ]]; then
	wdtcls=/sys/class/watchdog
	cd $wdtcls
	for dir in */; do
		cd $dir
		active=`[ -f state ] && cat state`
		if [ "$active" =  "active" ]; then
			# applications like kdump need to know that
			# which watchdog modules have been added
			# into initramfs
			echo `cat identity` >> "$initdir/lib/dracut/active-watchdogs"
			# device/modalias will return driver of this device
			wdtdrv=`cat device/modalias`
			# There can be more than one module represented by same
			# modalias. Currently load all of them.
			# TODO: Need to find a way to avoid any unwanted module
			# represented by modalias
			wdtdrv=`modprobe -R $wdtdrv | tr "\n" "," | sed 's/.$//'`
			instmods $wdtdrv
			# however in some cases, we also need to check that if
			# there is a specific driver for the parent bus/device.
			# In such cases we also need to enable driver for parent
			# bus/device.
			wdtppath="device/..";
			while [ -f "$wdtppath/modalias" ]
			do
				wdtpdrv=`cat $wdtppath/modalias`
				wdtpdrv=`modprobe -R $wdtpdrv | tr "\n" "," | sed 's/.$//'`
				instmods $wdtpdrv
				wdtppath="$wdtppath/.."
			done
		fi
		cd ..
	done
    fi
}
