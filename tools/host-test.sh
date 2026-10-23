#!/bin/sh
# Run on a ZimaOS host as root after `zpkg install /tmp/admintools.raw`:
# every tool does one real job, not just --version. Prints one line per tool, OK or FAIL.
#   sudo sh host-test.sh
set -u
T=$(mktemp -d /tmp/admintools-test.XXXXXX)
ok=0; bad=0
check() { # <name> <command...>
  n="$1"; shift
  if out=$("$@" 2>&1); then ok=$((ok + 1)); echo "OK   $n"; else bad=$((bad + 1)); echo "FAIL $n: $(echo "$out" | tail -n 2)"; fi
}

printf 'a\nb\n' > "$T/1"; printf 'a\nc\n' > "$T/2"
check diff     sh -c "diff -u '$T/1' '$T/2' | grep -qx '+c'"
check diff3    sh -c "diff3 '$T/1' '$T/2' '$T/1' >/dev/null; [ \$? -le 1 ]"
check sdiff    sh -c "sdiff '$T/1' '$T/2' >/dev/null; [ \$? -le 1 ]"
check nsenter  sh -c "[ \"\$(nsenter -t 1 -m readlink /proc/self/ns/mnt)\" = \"\$(readlink /proc/1/ns/mnt)\" ]"
check strace   sh -c "strace -f -e trace=execve true 2>&1 | grep -q execve"
check tcpdump-list sh -c "tcpdump -D | grep -q lo"
# A real capture, not just the interface list: Debian's tcpdump drops privileges to a user
# "tcpdump" that ZimaOS does not have ("Couldn't find user 'tcpdump'", measured 1.8.0).
check tcpdump  sh -c "timeout 8 tcpdump -ni lo -c 1 udp port 9 > '$T/td' 2>&1 & sleep 2; python3 -c 'import socket; socket.socket(socket.AF_INET, socket.SOCK_DGRAM).sendto(b\"x\", (\"127.0.0.1\", 9))'; wait; grep -q '1 packet captured' '$T/td' || { cat '$T/td'; false; }"
check socat    sh -c "echo hallo | socat - SYSTEM:cat | grep -qx hallo"
check pv       sh -c "head -c 1048576 /dev/zero | pv -q | wc -c | grep -qx 1048576"
check 7z       sh -c "cd '$T' && 7z a -bd x.7z 1 >/dev/null && mkdir out && 7z x -bd -oout x.7z >/dev/null && cmp 1 out/1"
check iotop    sh -c "iotop -b -n 1 -o >/dev/null"
check iftop    sh -c "timeout 10 iftop -t -s 1 -i lo 2>&1 | grep -q 'Total send rate'"
check screen   sh -c "screen -dmS admintoolstest sleep 3 && screen -ls | grep -q admintoolstest"
check mosh-server sh -c "mosh-server --version | grep -q mosh"
check ping-iputils sh -c "ping-iputils -c 1 -W 2 127.0.0.1 | grep -q '1 received'"
gw=$(ip route show default | awk '{print $3; exit}')
[ -z "$gw" ] || check ping-gateway sh -c "ping-iputils -c 2 -W 2 $gw | grep -q ' 0% packet loss\| 50% packet loss'"
# The bundled libraries must not leak into host tools: host grep without loader warnings.
check host-grep sh -c "! /usr/bin/grep --version 2>&1 | grep -q 'no version information'"
echo "admintools host-test: $ok OK, $bad FAIL"
rm -f "$T/1" "$T/2" "$T/x.7z" "$T/out/1" "$T/td"; rmdir "$T/out" "$T" 2>/dev/null
[ "$bad" -eq 0 ]
