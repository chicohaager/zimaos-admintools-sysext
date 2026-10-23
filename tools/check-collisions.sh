#!/bin/sh
# Run on the ZimaOS host BEFORE installing: lists every file of the image that the host already
# has in /usr. A sysext overlays /usr, so such a file would silently replace the host's own.
#   unsquashfs -lc admintools-amd64.raw | sed 's|^squashfs-root||' > files.txt   (build machine)
#   sh check-collisions.sh < files.txt                                            (host)
n=0; hit=0
while read -r f; do
  n=$((n + 1))
  case "$f" in */extension-release.d/*) continue ;; esac
  if [ -e "$f" ] || [ -L "$f" ]; then echo "COLLISION $f"; hit=$((hit + 1)); fi
done
echo "checked=$n collisions=$hit"
[ "$hit" -eq 0 ]
