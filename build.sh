#!/bin/sh
# Build the admintools sysext for ZimaOS.
#   sh build.sh [amd64|arm64]      (default: amd64)
# Output in dist/: admintools-<arch>.raw (+ .sha256), for amd64 also admintools.raw.
set -eu
cd "$(dirname "$0")"
ARCH="${1:-amd64}"
MODKIT="${LINTUX_MODKIT:-../lintux-modkit}"
[ -f "$MODKIT/sysext/bundle-debian.sh" ] || { echo "lintux-modkit with sysext/bundle-debian.sh not found at $MODKIT (set LINTUX_MODKIT)" >&2; exit 1; }
VERSION=$(cat VERSION)
go vet ./...
go test ./...

# Debian package -> programs taken from it. Only what ZimaOS 1.8.0 lacks (command -v on the host, 2026-10-23);
# cmp is left out: ZimaOS ships /usr/bin/cmp, and a sysext would shadow it (tools/check-collisions.sh).
PKGS="diffutils util-linux strace tcpdump socat pv 7zip iotop-c iftop screen mosh iputils-ping"
BINS="/usr/bin/diff /usr/bin/diff3 /usr/bin/sdiff /usr/bin/nsenter /usr/bin/strace /usr/bin/tcpdump
/usr/bin/socat /usr/bin/pv /usr/bin/7z /usr/lib/7zip/7z /usr/lib/7zip/7z.so /usr/sbin/iotop-c /usr/sbin/iftop /usr/bin/screen /usr/bin/mosh-server /usr/bin/ping"

rm -rf build/root
mkdir -p build/root
# shellcheck disable=SC2086
sh "$MODKIT/sysext/bundle-debian.sh" admintools build/root "$ARCH" "$PKGS" $BINS
ln -s iotop-c build/root/usr/sbin/iotop
# Debian's tcpdump drops privileges to a user "tcpdump" that ZimaOS lacks ("Couldn't find user
# 'tcpdump'", measured 1.8.0). The binary moves to usr/libexec (same depth: its RPATH stays right),
# /usr/bin/tcpdump passes -Z root first, so a -Z the caller gives still wins.
mkdir -p build/root/usr/libexec
mv build/root/usr/bin/tcpdump build/root/usr/libexec/admintools-tcpdump
printf '#!/bin/sh\nexec /usr/libexec/admintools-tcpdump -Z root "$@"\n' > build/root/usr/bin/tcpdump
chmod 755 build/root/usr/bin/tcpdump
# ZimaOS' own /usr/bin/ping is a BusyBox applet that exits 1 without output (measured 1.8.0);
# the working iputils ping gets its own name, so the host's file is not overlaid.
mv build/root/usr/bin/ping build/root/usr/bin/ping-iputils
# The tile: unit, module JSON (zpkg counts a module as installed only with
# /usr/share/casaos/modules/<name>.json — without it `zpkg install` answers "module not
# installed", rc=1, measured 1.8.0; its "services" make zpkg enable and start the web
# service), UI files, the web backend and the self-test it runs.
cp -a files/. build/root/
sh "$MODKIT/sysext/add-web.sh" admintools build/root "$VERSION"
CGO_ENABLED=0 GOOS=linux GOARCH="$ARCH" go build -trimpath -ldflags="-s -w -X main.version=$VERSION" \
  -o build/root/usr/bin/admintools-web ./cmd/admintools-web
mkdir -p build/root/usr/libexec/admintools
install -m 755 tools/host-test.sh build/root/usr/libexec/admintools/selftest.sh
sh "$MODKIT/sysext/build-sysext.sh" admintools build/root "$ARCH" dist "$VERSION"
# shellcheck disable=SC2086
sh tools/check-image.sh "dist/admintools-$ARCH.raw" $(printf '%s\n' $BINS | grep -vx /usr/bin/ping) /usr/sbin/iotop /usr/libexec/admintools-tcpdump /usr/bin/ping-iputils
cat "dist/admintools-$ARCH.raw.sha256"
