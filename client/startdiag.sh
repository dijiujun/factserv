#!/bin/sh -eu

# This script is part of published root and runs as early as possible during
# boot. Because it can't easily be changed it does the minimum work necessary
# to download a tarball from the factory server, then passes control to
# dodiag.sh from the tarball.

# This is the pionic controller's IP address. Note pionic forwards port 61080
# to the factory server port 80, and 61443 to factory server port 443. All
# server traffic should go via these ports.
pionicIP=192.168.111.1  # pionic controller IP address

# This is the factory detction method. If the DUT has a pre-defined static IP
# address at the time that this script runs, then use 'http'. Otherwise use
# 'beacon' (pionic must also be configured to start the beacon server).
method=http

# If 'beacon', this is the network interface that attaches to the pionic
# controller. Not required for http since the network must already be up.
interface=

# If 'beacon', the IP address to apply to the interface after beacon is
# detected (in the same subnet as pionic). Not required for http since the
# network must already be up.
address=

# The factory server has a self-signed https certificate. We verify the cert
# using the base-64 encoded sha256 of the public key. For reference, this can
# be obtained from the server with:
#
#   openssl s_client -connect X.X.X.X:443 </dev/null 2>/dev/null | openssl x509 -pubkey -noout | sed '/----/d' | base64 -d -w0 | openssl dgst -sha256 -binary | base64
#
# PLEASE NOTE there are two server certs. The development cert is insecure and
# must never be used in production. Production servers use a secret production
# cert, add its hash below once it's been defined.
#
# The production cert MUST remain secret, and the development hash MUST NOT be
# supported in production or your systems WILL BE HACKABLE.
#
# You have two options:
#
#   A) conditionally define the development hash below if you can unambiguously
#   detect development code or development hardware at this point in the boot.
#   You will be able to test development builds against development and
#   production servers. However you will not be able to test production builds
#   against development servers.
#
#   B) delete the development hash entirely once the production cert is
#   defined, and deploy the production cert to development servers. You will be
#   able to test any build against any server, however there is an increased
#   chance that the production cert will leak.

development="paYQewbP520iAv1hIi/A1lvYyVzMdDv6yEmp9El0aPc="
production=""

# print message and exit
die() { echo $* >&2; exit 1; }

# XXX define the work directory. Ideally it should be in a ramdisk so
# downloaded diagnostic code doesn't survive reboot (assume worst case size
# 256M). But in case it's persistent, try to delete it here anyway.  If the
# delete fails then something is very wrong.
workspace=/tmp/diagwork
rm -rf $workspace
[ ! -e $workspace ] || die "Can't remove $workspace!"

curl="curl -qsSf"

# Try to detect the factory.
case "$method" in
    beacon)
        # Listen for an ethernet beacon. If we don't hear one then
        # assume we're not in the factory and just exit
        beacon recv 2 $interface pionic >/dev/null || exit 0
        # There is no exit after this point
        echo "Beacon detected, configuring $interface for $address"
        ip link set $interface up || true
        ip address add $address dev $interface || true
        ;;

    http)
        # We expect that $pionicIP is on the local subnet and forwards port 61080
        # to the server http, and 61433 to the server https. Perform a server
        # 'fixture' connect, if it doesn't work then assume we're not in the
        # factory and just quietly exit.
        $curl -m 2 "http://$pionicIP:61080/cgi-bin/factory?service=fixture" >/dev/null 2>/dev/null || exit 0
        ;;

    *)
        die "Invalid method $method"
        ;;
esac

# Here, we're in factory mode, there is no escape

# given forground and background colors, and up to 24 character text, display pionic badge
badge() {
    [ -z "$(echo -e)" ] && echo="echo -e" || echo="echo"
    $echo $3 | $curl --data-binary @- "http://$pionicIP/display?text&badge&fg=$1&bg=$2&size=60" || die "Display update failed"
}

# spin forever, after writing exit screen
stop() { set -eu; trap '' EXIT; while true; do echo "Reboot now"; sleep 30; done; }

# on unexpected exit, display error and stop
trap 'set +eu; badge white red "Unexpected error\nError inesperado\n意外的错误"; stop;' EXIT

# Ok we're launching, tell operator
badge white black "Starting\nComenzando\nn开始"

# XXX set the build ID. The build ID must uniquely identify the software build
# and the DUT device type. Note the server associates the build ID with a
# specific tarball containing the diagnostic code, therefore the build string
# must be predictable and readable by humans.
buildID=test
echo "Using buildID $buildID"

# Create the empty work directory and make it the current working directory.
mkdir -p $workspace
cd $workspace

# Retrieve the diagnostic tarball from the server https (via pionic port 61443)
# and unpack it into the current directory. Verify the hash of the https
# certificate public key, so we can trust that the tarball really did come from
# the factory server and not from someone's laptop. If both hashes are defined,
# try the production hash first. The development hash MUST NOT be defined for
# production software, see the note above.
for pubkey in ${production:-} ${development:-}; do
    echo "Downloading with key hash $pubkey"
    if $curl -k --pinnedpubkey "sha256//$pubkey" --form-string "buildid=$buildID" "https://$pionicIP:61443/cgi-bin/factory?service=download" | tar -xzv; then
        [ -x ./dodiag.sh ] || die "Tarball does not contain dodiag.sh"
        # invoke with parameters of interest, it should not return
        ./dodiag.sh $pionicIP $buildID
        die "dodiag.sh failed with status $?"
    fi
done
die "Tarball download failed"
