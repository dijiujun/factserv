#!/bin/sh -eu

# This script is part of published root and runs as early as possible during
# boot. Because it can't easily be changed it does the minimum work necessary
# to download a tarball from the factory server, then passes control to
# dodiag.sh from the tarball.

# This is the factory detction method. If the DUT has a pre-defined static IP
# address at the time that this script runs, then use 'http'. Otherwise use
# 'beacon' (pionic must also be configured to start the beacon server).
method=http

# If 'beacon', this is the network interface that attaches to the pionic
# controller. Not required for http since the network must already be up.
interface=

# If 'pionic' is set (to anything), then the DUT is attached to a pionic test
# station controller. If undefined then the DUT is attached directly to server
# via a USB ethernet dongle.
pionic=yes

# The factory server has a self-signed https certificate. We verify the cert
# using the base-64 encoded sha256 of the public key. For reference, this can
# be obtained from the server with:
#
#   openssl s_client -connect X.X.X.X:443 </dev/null 2>/dev/null | openssl x509 -pubkey -noout | sed '/----/d' | base64 -d -w0 | openssl dgst -sha256 -binary | base64
#
# PLEASE NOTE there are two server certs. The development cert is insecure and
# must never be used in real production. Production servers use a secret
# production cert, add its hash below once it's been defined.
#
# The production cert MUST remain secret, and the development hash MUST NOT be
# supported by production hardware or your systems WILL BE HACKABLE.
#
# You have two options:
#
#   A) If you can unambiguously detect development vs production harware at
#   this point in the boot then update the 'allow_insecure_server()' function
#   accordingly. This will allow you to test development systems against
#   development or production servers. However you will not be able to test
#   production systems against development servers.
#
#   B) Delete the development hash entirely once the production cert is
#   defined, and deploy the production cert to development servers. You will be
#   able to test any build against any server, however there is an increased
#   chance that the production cert will leak from the presumably less-secure
#   development server.

# Hashes for development and production servers.
development="paYQewbP520iAv1hIi/A1lvYyVzMdDv6yEmp9El0aPc="
production=""

# This must return true in order to use the development hash. In this example
# script it always returns true. In real life, if option A is used it must
# return true only if running on a development hardware platform. If option B
# is used it should return false (but the development hash should be removed
# anyway).
allow_insecure_server() { true; }

# disallow the development hash on production hardware
allow_insecure_server() || unset development

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

# Try to detect the factory. Note this introduces a 2 second delay in the
# normal non-factory boot process.
case "$method" in
    beacon)
        ip link set $interface up || true
        # Listen for an ethernet beacon containing the word 'pionic'. If we're
        # not in the factory then we'll timeout after two seconds.
        beacon recv 2 $interface pionic >/dev/null || exit 0
        # There is no exit after this point
        echo "Beacon detected, requesting an IP address on $interface"
        # Use dora to perform DHCP (https://github.com//glitchub/dora). It
        # prints the string:
        #   address/XX subnet broadcast router dnsserver domainname dhcpserver lease
        # We only care about the address and broadcast
        set -- $(dora -m acquire $interface)
        [ $# != 0 ] || die "dora failed"
        ip address add $1 broadcast $3 dev $interface
        # Could also use:
        #   set -- $(dora acquire $interface)
        #   [ $# != 0 ] || die "dora failed"
        #   ifconfig $interface $1 broadcast $3
        ;;

    http)
        # Try to connect to factory.server via https. If we're not in the
        # factory then factory.server won't resolve and we'll timeout after two
        # seconds.
        $curl -m 2 -k "https://factory.server/cgi-bin/factory?service=fixture" >/dev/null 2>/dev/null || exit 0
        ;;

    *)
        die "Invalid method $method"
        ;;
esac

# Here, we're in factory mode, there is no escape

# Spin forever on exit
stop() { set -eu; trap '' EXIT; while true; do echo "Reboot now"; sleep 30; done; }
trap 'set +eu; stop;' EXIT

if  [ "$pionic" ]; then

    # Given forground and background colors, and some amount of text, display via pionic
    display() {
        [ -z "$(echo -e)" ] && echo="echo -e" || echo="echo" # workaround bash vs dash
        $echo $3 | $curl --data-binary @- "http://pionic.server/display?text&badge&fg=$1&bg=$2" || die "Display update failed"
    }

    # On unexpected exit, display error and stop
    trap 'set +eu; display white red "Unexpected error\nError inesperado\n意外的错误"; stop;' EXIT

    # Ok we're launching, tell operator
    display white black "Starting\nComenzando\nn开始"
fi

# XXX set the build ID. The build ID must uniquely identify the software build
# and the DUT device type. Note the server associates the build ID with a
# specific tarball containing the diagnostic code, therefore the build string
# must be predictable and readable by humans.
buildID=test
echo "Using buildID $buildID"

# Create the empty work directory and make it the current working directory.
mkdir -p $workspace
cd $workspace

# Retrieve the diagnostic tarball from factory.server https and unpack it into
# the current directory. Verify the hash of the https certificate public key,
# so we can trust that the tarball really did come from the factory server and
# not from someone's laptop. If both hashes are defined, try the production
# hash first. The development hash MUST NOT be defined for production software,
# see the note above.
for pubkey in ${production:-} ${development:-}; do
    echo "Downloading with key hash $pubkey"
    if $curl -k --pinnedpubkey "sha256//$pubkey" --form-string "buildid=$buildID" "https://factory.server/cgi-bin/factory?service=download" | tar -xzv; then
        [ -x ./dodiag.sh ] || die "Tarball does not contain dodiag.sh"
        # invoke with parameters of interest, it should not return
        ./dodiag.sh $buildID
        die "dodiag.sh failed with status $?"
    fi
done
die "Tarball download failed"
