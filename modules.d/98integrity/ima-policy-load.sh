#!/bin/sh

# Licensed under the GPLv2
#
# Copyright (C) 2011 Politecnico di Torino, Italy
#                    TORSEC group -- http://security.polito.it
# Roberto Sassu <roberto.sassu@polito.it>
#
# Copyright (C) 2016 IBM Corporation
#
# Stefan Berger <stefanb@linux.vnet.ibm.com>
#

IMASECDIR="${SECURITYFSDIR}/ima"
IMACONFIG="${NEWROOT}/etc/ima/ima"
IMAPOLICY="/etc/ima/ima-policy"

# for backwards compatibility
IMACONFIG_OLD="${NEWROOT}/etc/sysconfig/ima"
IMAPOLICY_OLD="/etc/sysconfig/ima-policy"

load_ima_policy()
{
    # check kernel support for IMA
    if [ ! -e "${IMASECDIR}" ]; then
        if [ "${RD_DEBUG}" = "yes" ]; then
            info "integrity: IMA kernel support is disabled"
        fi
        return 0
    fi

    # override the default configuration
    if [ -f "${IMACONFIG}" ]; then
        . ${IMACONFIG}
    elif [ -f "${IMACONFIG_OLD}" ]; then
        . ${IMACONFIG_OLD}
    fi

    # set the IMA policy path name
    IMAPOLICYPATH="${NEWROOT}${IMAPOLICY}"
    [ ! -f "${IMAPOLICYPATH}" ] && \
        IMAPOLICYPATH="${NEWROOT}${IMAPOLICY_OLD}"

    # check the existence of the IMA policy file
    [ -f "${IMAPOLICYPATH}" ] && {
        info "Loading the provided IMA custom policy";
        printf '%s' "${IMAPOLICYPATH}" > ${IMASECDIR}/policy || \
            cat "${IMAPOLICYPATH}" > ${IMASECDIR}/policy
    }

    return 0
}

load_ima_policy
