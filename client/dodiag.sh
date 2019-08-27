#!/bin/sh -eu

# This script is part of the diagnostic tarball. It is run by startdiag.sh to
# do all deferrable initialization and then runs dodiag to actually perform
# the tests and interaction with the server.

# Abort with message
die() { echo $* >&2; exit 1; }

[ $# = 2 ] || die "Usage: dodiag.sh pionicIP buildID"
pionicIP=$1 buildID=$2

# The current directory contains the downloaded diagnostics, make sure that the
# dodiag program is there.
[ -x ./dodiag ] || die "No executable dodiag"

# XXX do board-specific pre-diag initialization here, start daemons and insmod device
# drivers, etc, in preparation for performing diagnostics.

# XXX get the device ID here. In real life it will be stored in some
# non-volatile storage. If it's not, then a device ID must be created. The
# exact method is system specific. For this demo we keep the deviceid in
# /tmp/deviceid. If missing or invalid then we try to read the PCB barcode and
# use that as the basis of our device ID. Don't use a file in production code!
deviceID=$(cat /tmp/deviceid 2>/dev/null) || true
case "$deviceID" in
    TEST-??????*)
        # TEST- and at least 6 characters, looks good!
        newdevice="" # not a new device
        ;;
    *)
        barcode=$(./getbar $pionicIP $buildID) || die "Failed to read barcode"
        [ ${#barcode} -eq 6 ] || die "Barcode '$barcode' is too short"
        deviceID="TEST-$barcode"
        echo "$deviceID" > /tmp/deviceid
        newdevice="-n" # tell dodiag to register a new deviceID, forces phase 1 operation
        ;;
esac

# Now invoke dodiag to talk to the server and run the tests
./dodiag $newdevice -p$pionicIP $buildID $deviceID
die "dodiag exit with status $?"
