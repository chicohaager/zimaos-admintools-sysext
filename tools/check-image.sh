#!/bin/sh
# Check a built image: every listed program is in it, every ELF program finds its libraries
# inside the image (RPATH into usr/lib/admintools), and extension-release carries a version.
#   sh tools/check-image.sh <image.raw> <program>...
set -eu
IMG="${1:?image}"; shift
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
unsquashfs -q -d "$T/r" "$IMG" >/dev/null
fail=0
for p in "$@"; do
  f="$T/r$p"
  if [ ! -e "$f" ]; then echo "FEHLT $p"; fail=1; continue; fi
  if ! file -bL "$f" | grep -q '^ELF'; then
    # A wrapper script: what it execs must be in the image too (Debian's 7z is one).
    for t in $(sed -n 's/^exec \(\/[^ ]*\).*/\1/p' "$f"); do
      [ -e "$T/r$t" ] || { echo "SKRIPT $p ruft $t auf - fehlt im Image"; fail=1; }
    done
    continue
  fi
  rp=$(readelf -d "$f" | sed -n 's/.*(RUNPATH).*\[\(.*\)\]/\1/p')
  case "$rp" in *usr/lib/admintools) ;; *) echo "RPATH $p: '$rp'"; fail=1 ;; esac
done
# Every library any program or library needs must be in the image or be part of the glibc core
# (the host provides that). ldd would quietly resolve the rest from the build machine.
for f in $(find "$T/r/usr/bin" "$T/r/usr/sbin" "$T/r/usr/lib" -type f 2>/dev/null); do
  file -b "$f" | grep -q '^ELF' || continue
  for n in $(readelf -d "$f" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
    echo "$n" | grep -qE '^(libc|libm|libpthread|libdl|librt|ld-linux-x86-64|ld-linux-aarch64|libresolv|libutil|libmvec)\.so' && continue
    [ -e "$T/r/usr/lib/admintools/$n" ] || { echo "LIB fehlt: $n (gebraucht von ${f#"$T/r"})"; fail=1; }
  done
done
grep -q '^SYSEXT_VERSION_ID=' "$T/r/usr/lib/extension-release.d/extension-release.admintools" || { echo "keine SYSEXT_VERSION_ID"; fail=1; }
[ "$fail" = 0 ] && echo "check-image: $# Programme gut" || { echo "check-image: FEHLER"; exit 1; }
