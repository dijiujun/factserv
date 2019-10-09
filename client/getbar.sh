#/bin/sh -eu

# If a barcode is already proivisioned for this device then just exit.

# Otherwise prompt the operator to scan a barcode, verify it matches the
# specified regex, and save in provisioned table.

# print message and exit
die() { echo $* >&2; exit 1; }

# check variables installed by dodiag
[ -n "${PIONICIP:-}" ] || die 'Requires $PIONICIP'
[ -n "${DEVICEID:-}" ] || die 'Requires $DEVICEID'

[ $# -eq 1 ] || die "Usage: getbar regex"
regex=$1

curl="curl -qsSf"

# given forground and background colors, and up to 24 character text, display pionic badge
badge() {
    [ -z "$(echo -e)" ] && echo="echo -e" || echo="echo"
    $echo $3 | $curl --data-binary @- "http://$PIONICIP/display?text&badge&fg=$1&bg=$2&size=60" || die "Display update failed"
}

# given column name, return provisioned data or ""
getprovision() {
    echo "Getting provisioned $1..." >&2
    $curl "http://$PIONICIP:61080/cgi-bin/factory?service=getprovision&deviceid=$DEVICEID&key=$1" || die "getprovision failed"
}

# given column name, provision with data on stdin
setprovision() {
    echo Setting provisioned $1... >&2
    $curl -F value=@- "http://$PIONICIP:61080/cgi-bin/factory?service=setprovision&deviceid=$DEVICEID&key=$1" || die "setprovision failed"
}

# get the current provisioned barcode
current=$(getprovision barcode)

if [ "$current" ]; then
    echo "Current barcode is '$current'" >&2
    exit 0
fi

echo "Requesting scan" >&2
flush="&flush" # flush on the first scan
while true; do
    badge black yellow "Scan barcode\nEscanear código\n扫描条形码"
    if ! barcode=$($curl "http://$PIONICIP/getbar?timeout=5$flush" 2>&1); then
        echo $barcode | grep -q 'Timeout$' || die "getbar failed: $barcode"
    else
        echo "Testing '$barcode' against '$regex'" >&2
        echo $barcode | grep -q -E "$regex" && break
        echo "Barcode is invalid" >&2
        badge red white "Invalid barcode\nCódigo inválido\n条形码无效"
        sleep 2
    fi
    flush="" # don't flush again
done

echo "Barcode is valid" >&2
badge white blue "Scan OK\nEscanear OK\n扫描确定"
echo $barcode | setprovision barcode

exit 0
