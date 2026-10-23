# admintools for ZimaOS

**Version 1.1.0** · ZimaOS 1.8.0 (amd64) · sysext module `admintools`

Command-line tools that ZimaOS does not ship, as one `systemd-sysext` module. The tools are there in the ZimaOS terminal and over SSH; the **Admin Tools** tile on the dashboard lists them with their versions and runs a self-test (every tool does one real job on the host — the same script as `tools/host-test.sh`).

| Tool | What for |
|---|---|
| `diff`, `diff3`, `sdiff` | compare files and configs |
| `nsenter` | run a command in another namespace, e.g. a container's or PID 1's mount namespace |
| `strace` | trace the system calls of a process |
| `tcpdump` | capture network traffic (runs as root: Debian's build would switch to a user `tcpdump` that ZimaOS lacks, so `/usr/bin/tcpdump` adds `-Z root`; a `-Z` you pass wins) |
| `socat` | relay and test sockets |
| `pv` | progress and throughput of a pipe |
| `7z` | 7-Zip archives |
| `iotop` (`iotop-c`) | disk I/O per process |
| `iftop` | network bandwidth per connection |
| `screen` | sessions that survive a lost SSH connection |
| `mosh-server` | server side of [mosh](https://mosh.org) |
| `ping-iputils` | a working `ping` (iputils) — ZimaOS' own `/usr/bin/ping` is a BusyBox applet that exits 1 without output (measured 1.8.0); the module does not replace it, so it has its own name |

Only tools ZimaOS 1.8.0 lacks are in it (`command -v` on the host, 2026-10-23). `cmp` is left out on purpose: ZimaOS ships `/usr/bin/cmp`, and a sysext overlays `/usr`, so its copy would replace the host's.

## Where the programs come from

From Debian 13 (trixie), packaged with [lintux-modkit](https://github.com/chicohaager/lintux-modkit)'s `sysext/bundle-debian.sh`:

- the programs go to `/usr/bin` and `/usr/sbin`, their libraries to `/usr/lib/admintools/` — they never replace a library of ZimaOS;
- each program finds its libraries through its RPATH, not through `LD_LIBRARY_PATH`, so nothing leaks into the host's own tools;
- glibc is the host's (Debian 13 has 2.41, ZimaOS 1.8.0 has 2.42; the build refuses a program that needs a newer one);
- `/usr/share/doc/admintools/packages.txt` lists every Debian package and version inside, `/usr/share/doc/admintools/<package>/copyright` holds its license.

The versions are Debian stable's, which receive Debian's security fixes. Some upstream projects are further ahead (strace, tcpdump); a new module release picks up whatever Debian 13 ships then.

## Install (on the ZimaOS host)

```sh
cd /tmp
curl -fsSLO https://github.com/chicohaager/zimaos-admintools-sysext/releases/latest/download/admintools-amd64.raw
curl -fsSLO https://github.com/chicohaager/zimaos-admintools-sysext/releases/latest/download/admintools-amd64.raw.sha256
sha256sum -c admintools-amd64.raw.sha256
mv admintools-amd64.raw admintools.raw      # zpkg takes the module name from the file name
sudo zpkg install /tmp/admintools.raw       # update: sudo zpkg install --force /tmp/admintools.raw
```

Remove with `sudo zpkg remove admintools`.

## Build

```sh
sh build.sh amd64     # needs docker, Go, node, squashfs-tools, binutils and ../lintux-modkit
```

`dist/admintools-amd64.raw` (+ `.sha256`). The build ends with `tools/check-image.sh`: every program is in the image, has its RPATH, and every library it or its libraries need is inside or part of the glibc core.

## Test on a host

```sh
unsquashfs -lc dist/admintools-amd64.raw | sed 's|^squashfs-root||' > files.txt
sh tools/check-collisions.sh < files.txt     # on the host, before installing: must report 0 collisions
sudo sh tools/host-test.sh                   # on the host, after installing: every tool does one real job
```

Run `check-collisions.sh` before the first install — once the module is merged, its own files are in `/usr` and show up as collisions.

Measured on ZimaOS 1.8.0 (ZimaBoard 2), 2026-10-23: 78 files, 0 collisions (the same check flagged `/usr/bin/cmp` while it was still in the image); before the install all tool checks failed, after it the host test reported 15 OK, 0 FAIL — the tools including a real `tcpdump` capture, plus the check that the host's `grep` stays undisturbed. No running process on the host had loaded a library from `/usr/lib/admintools/` (all 260 `/proc/*/maps` read as root; a `screen` session as positive control was the only one).

**Note:** `ping` on ZimaOS 1.8.0 is a BusyBox applet that exits 1 without any output, even for `--help` (measured on the same host). This module does not replace it — a file at `/usr/bin/ping` would overlay the host's own — and ships `ping-iputils` instead.

MIT License for this repository, see [LICENSE](LICENSE). The bundled programs keep their own licenses (GPL and others), shipped inside the image.
