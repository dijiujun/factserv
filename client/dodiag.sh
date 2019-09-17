#!/bin/sh -eu

# This script is part of the diagnostic tarball. It is run by startdiag.sh to
# perform all deferrable initialization and then runs dodiag to actually
# perform the tests and interaction with the server.

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

# Return true if given regex matches first line of stdin
match() { python -c 'import re,sys; sys.exit(0 if re.compile(sys.argv[1]).match(sys.stdin.readline().rstrip()) else 1)' "$1"; }

# Given a glob pattern, scan barcodes until one matches the pattern and return it on stdout.
getbar()
{
    regex=$1
    flush="&flush" # flush on the first scan
    while true; do
        badge black yellow "Scan barcode\nEscanear código\n扫描条形码"
        if ! out=$($curl "http://$pionicIP/getbar?timeout=5$flush" 2>&1); then
            if ! echo $out | match '.*Timeout$'; then
                echo "getbar failed: $out" >&2
                badge black red "Scan failed\nEscanear fallido\n扫描失败"
                spin  
            fi
        else
            # is it a match?
            echo $out | match "$regex" && break
            # no
            badge red white "Invalid barcode\nCódigo inválido\n条形码无效"
            sleep 2
        fi
        flush=""
    done
    badge white blue "Scan OK\nEscanear OK\n扫描确定"
    echo $out
}

# Make sure current directory contains downloaded diagnostics
[ -x ./dodiag ] || die "No executable dodiag"

# XXX do board-specific pre-diag initialization here, start daemons and insmod device
# drivers, etc, in preparation for performing diagnostics.

# XXX get the device ID here. In real life it is stored in some non-volatile
# storage. If it's not, then a device ID must be created. The exact method is
# system specific. For this demo we keep the deviceid in /tmp/deviceid (don't
# do this in production). If missing or invalid then we ask pionic to read the
# PCB barcode and use that as the basis of our device ID.
deviceID=$(cat /tmp/deviceid 2>/dev/null) || true
# we expect TEST- and at least 6 chars
if echo $deviceID | match '^TEST-{6}'; then
    newdevice="" # we're good to go   
else
    if  ! $curl "http://$pionicIP:61080/cgi-bin/factory?service=newdevice&buildid=$buildID" >/dev/null; then
        echo "Build ID $buildID  phase 1 not allowed" >&2
        badge red white "Not allowed\nNo permitido\n不允许"
        spin
    fi 
    # Get barcode at least 6 characters
    barcode=$(getbar '^.{6}')
    deviceID="TEST-$barcode"
    echo "$deviceID" > /tmp/deviceid
    newdevice="-n" # tell dodiag to register a new deviceID, forces phase 1 operation
fi

# Now invoke dodiag to run the tests, it should not return.
python dodiag $newdevice -p$pionicIP $buildID $deviceID
die "dodiag failed with status $?"
