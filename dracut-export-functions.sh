#!/bin/bash
#
# functions used by dracut and other tools.
#
# Copyright 2015 Red Hat, Inc.  All rights reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# Generic substring function.  If $2 is in $1, return 0.
strstr() { [[ $1 = *"$2"* ]]; }
# Generic glob matching function. If glob pattern $2 matches anywhere in $1, OK
strglobin() { [[ $1 = *$2* ]]; }
# Generic glob matching function. If glob pattern $2 matches all of $1, OK
strglob() { [[ $1 = $2 ]]; }
# returns OK if $1 contains literal string $2 at the beginning, and isn't empty
str_starts() { [ "${1#"$2"*}" != "$1" ]; }
# returns OK if $1 contains literal string $2 at the end, and isn't empty
str_ends() { [ "${1%*"$2"}" != "$1" ]; }

# get_maj_min <device>
# Prints the major and minor of a device node.
# Example:
# $ get_maj_min /dev/sda2
# 8:2
get_maj_min() {
    local _maj _min _majmin
    _majmin="$(stat -L -c '%t:%T' "$1" 2>/dev/null)"
    printf "%s" "$((0x${_majmin%:*})):$((0x${_majmin#*:}))"
}

# get a persistent path from a device
get_persistent_dev() {
    local i _tmp _dev

    _dev=$(get_maj_min "$1")
    [ -z "$_dev" ] && return

    for i in \
        /dev/mapper/* \
        /dev/disk/${persistent_policy:-by-uuid}/* \
        /dev/disk/by-uuid/* \
        /dev/disk/by-label/* \
        /dev/disk/by-partuuid/* \
        /dev/disk/by-partlabel/* \
        /dev/disk/by-id/* \
        /dev/disk/by-path/* \
        ; do
        [[ -e "$i" ]] || continue
        [[ $i == /dev/mapper/control ]] && continue
        [[ $i == /dev/mapper/mpath* ]] && continue
        _tmp=$(get_maj_min "$i")
        if [ "$_tmp" = "$_dev" ]; then
            printf -- "%s" "$i"
            return
        fi
    done
    printf -- "%s" "$1"
}

# ugly workaround for the lvm design
# There is no volume group device,
# so, there are no slave devices for volume groups.
# Logical volumes only have the slave devices they really live on,
# but you cannot create the logical volume without the volume group.
# And the volume group might be bigger than the devices the LV needs.
check_vol_slaves() {
    local _lv _vg _pv _dm
    for i in /dev/mapper/*; do
        [[ $i == /dev/mapper/control ]] && continue
        _lv=$(get_maj_min $i)
        _dm=/sys/dev/block/$_lv/dm
        [[ -f $_dm/uuid  && $(<$_dm/uuid) =~ LVM-* ]] || continue
        if [[ $_lv = $2 ]]; then
            _vg=$(lvm lvs --noheadings -o vg_name $i 2>/dev/null)
            # strip space
            _vg=$(printf "%s\n" "$_vg")
            if [[ $_vg ]]; then
                for _pv in $(lvm vgs --noheadings -o pv_name "$_vg" 2>/dev/null)
                do
                    check_block_and_slaves $1 $(get_maj_min $_pv) && return 0
                done
            fi
        fi
    done
    return 1
}

# Not every device in /dev/mapper should be examined.
# If it is an LVM device, touch only devices which have /dev/VG/LV symlink.
lvm_internal_dev() {
    local dev_dm_dir=/sys/dev/block/$1/dm
    [[ ! -f $dev_dm_dir/uuid || $(<$dev_dm_dir/uuid) != LVM-* ]] && return 1 # Not an LVM device
    local DM_VG_NAME DM_LV_NAME DM_LV_LAYER
    eval $(dmsetup splitname --nameprefixes --noheadings --rows "$(<$dev_dm_dir/name)" 2>/dev/null)
    [[ ${DM_VG_NAME} ]] && [[ ${DM_LV_NAME} ]] || return 0 # Better skip this!
    [[ ${DM_LV_LAYER} ]] || [[ ! -L /dev/${DM_VG_NAME}/${DM_LV_NAME} ]]
}

# Walk all the slave relationships for a given block device.
# Stop when our helper function returns success
# $1 = function to call on every found block device
# $2 = block device in major:minor format
check_block_and_slaves() {
    local _x
    [[ -b /dev/block/$2 ]] || return 1 # Not a block device? So sorry.
    if ! lvm_internal_dev $2; then "$1" $2 && return; fi
    check_vol_slaves "$@" && return 0
    if [[ -f /sys/dev/block/$2/../dev ]]; then
        check_block_and_slaves $1 $(<"/sys/dev/block/$2/../dev") && return 0
    fi
    [[ -d /sys/dev/block/$2/slaves ]] || return 1
    for _x in /sys/dev/block/$2/slaves/*/dev; do
        [[ -f $_x ]] || continue
        check_block_and_slaves $1 $(<"$_x") && return 0
    done
    return 1
}
