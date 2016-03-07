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
    # Do not add watchdog hooks if systemd module is included
    # In that case, systemd will manage watchdog kick
    if dracut_module_included "systemd"; then
	    return
    fi
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
    wdtcmdline=""
    cd /sys/class/watchdog
    for dir in */; do
	    cd $dir
	    active=`[ -f state ] && cat state`
	    if ! [[ $hostonly ]] || [[ "$active" =  "active" ]]; then
		    # device/modalias will return driver of this device
		    wdtdrv=`cat device/modalias`
		    # There can be more than one module represented by same
		    # modalias. Currently load all of them.
		    # TODO: Need to find a way to avoid any unwanted module
		    # represented by modalias
		    wdtdrv=`modprobe -R $wdtdrv | tr "\n" "," | sed 's/.$//'`
		    instmods $wdtdrv
		    wdtcmdline="$wdtcmdline$wdtdrv,"
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
			    wdtcmdline="$wdtcmdline$wdtpdrv,"
			    wdtppath="$wdtppath/.."
		    done
	    fi
	    cd ..
    done
    # ensure that watchdog module is loaded as early as possible
    if [[ $wdtcmdline ]]; then
	    echo "rd.driver.pre=$wdtcmdline" > ${initdir}/etc/cmdline.d/04-watchdog.conf
    fi
}
