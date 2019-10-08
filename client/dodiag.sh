#!/bin/sh -eu

# This script is part of the diagnostic tarball. It is run by startdiag.sh to
# perform all deferrable initialization, then runs dodiag to actually perform
# the tests and interact with the server.

# print message and exit
die() { echo $* >&2; exit 1; }

[ $# = 2 ] || die "Usage: dodiag.sh pionicIP buildID"
pionicIP=$1
buildID=$2

curl="curl -qsSf"

# given forground and background colors, and up to 24 character text, display pionic badge
badge() {
    [ -z "$(echo -e)" ] && echo="echo -e" || echo="echo"
    $echo $3 | $curl -qsSf --data-binary @- "http://$pionicIP/display?text&badge&fg=$1&bg=$2&size=60" || die "Display update failed"
}

# spin forever, after writing an error screen
spin() { set -eu; trap '' EXIT; while true; do echo "Reboot now"; sleep 30; done; }

# on unexpected exit, display error and spin
trap 'set +eu; badge white red "Unexpected error\nError inesperado\n意外的错误"; spin;' EXIT

# Make sure current directory contains downloaded diagnostics
[ -x ./dodiag ] || die "No executable dodiag"

# XXX do board-specific pre-diag initialization here, start daemons and insmod device
# drivers, etc, in preparation for performing diagnostics.

# XXX get the device ID here, for this demo it's kept in /tmp/deviceid.
# In real production it should be stored in flash or eeprom. 
deviceID=$(cat /tmp/deviceid 2>/dev/null) || true

# We expect the device ID to be "DEMO-" followed by 12 hex characters
if echo $deviceID | grep -q -E '^DEMO-[0-9A-F]{12}$'; then
    echo "Current device ID is '$deviceID'"
else    
    # The device ID doesn't exist or is invalid, ask the server for a new one.
    # Request will fail if phase1 not allowed on this test station.
    echo "Requesting new device ID"
    if ! deviceID=$($curl "http://$pionicIP:61080/cgi-bin/factory?service=gendevice&buildid=$buildID") >/dev/null; then
        echo "Phase 1 is not allowed!" >&2
        badge red white "Not allowed\nNo permitido\n不允许"
        spin
    fi
    # For this demo, prefix the device ID with "DEMO-". Note phase1 testing is
    # responsible for storing the deviceID (typically the first test).
    deviceID=DEMO-$deviceID
fi

# Invoke dodiag to run the tests, it should not return.
echo "Starting './dodiag -p$pionicIP $buildID $deviceID'"
python ./dodiag -p$pionicIP $buildID $deviceID
die "dodiag failed with status $?"
