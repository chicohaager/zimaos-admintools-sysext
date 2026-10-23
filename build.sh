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

# Debian package -> programs taken from it. Only what ZimaOS 1.8.0 lacks (command -v on the host, 2026-10-23);
# cmp is left out: ZimaOS ships /usr/bin/cmp, and a sysext would shadow it (tools/check-collisions.sh).
PKGS="diffutils util-linux strace tcpdump socat pv 7zip iotop-c iftop screen mosh"
BINS="/usr/bin/diff /usr/bin/diff3 /usr/bin/sdiff /usr/bin/nsenter /usr/bin/strace /usr/bin/tcpdump
/usr/bin/socat /usr/bin/pv /usr/bin/7z /usr/lib/7zip/7z /usr/lib/7zip/7z.so /usr/sbin/iotop-c /usr/sbin/iftop /usr/bin/screen /usr/bin/mosh-server"

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
# zpkg counts a module as installed only with /usr/share/casaos/modules/<name>.json; without it
# `zpkg install` merges the image but answers "module not installed", rc=1 (measured 1.8.0, 2026-10-23).
# No "ui" key: no dashboard tile. "version" is what `zpkg list` shows (as for IceWhale's zimanet).
mkdir -p build/root/usr/share/casaos/modules
printf '{\n  "name": "admintools",\n  "version": "v%s"\n}\n' "$VERSION" > build/root/usr/share/casaos/modules/admintools.json
sh "$MODKIT/sysext/build-sysext.sh" admintools build/root "$ARCH" dist "$VERSION"
# shellcheck disable=SC2086
sh tools/check-image.sh "dist/admintools-$ARCH.raw" $BINS /usr/sbin/iotop /usr/libexec/admintools-tcpdump
cat "dist/admintools-$ARCH.raw.sha256"
