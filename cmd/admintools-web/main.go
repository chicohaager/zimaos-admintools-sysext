// Command admintools-web serves the admintools tile: which tools the module
// brings, their Debian package versions, and a self-test that runs every tool
// once (/usr/libexec/admintools/selftest.sh, the same script as tools/host-test.sh).
package main

import (
	"bufio"
	"context"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/chicohaager/lintux-modkit/httpx"
	"github.com/chicohaager/lintux-modkit/webmod"
)

// version is set at build time from VERSION (-ldflags -X main.version=...).
var version = "dev"

// Tool is one program of the module.
type Tool struct {
	Name        string `json:"name"`
	Path        string `json:"path"`
	Package     string `json:"package"`
	Description string `json:"description"`
	Version     string `json:"version"`
	Present     bool   `json:"present"`
}

// tools lists what the image ships; versions come from packages.txt.
var tools = []Tool{
	{Name: "diff", Path: "/usr/bin/diff", Package: "diffutils", Description: "compare files and configs"},
	{Name: "diff3", Path: "/usr/bin/diff3", Package: "diffutils", Description: "three-way compare"},
	{Name: "sdiff", Path: "/usr/bin/sdiff", Package: "diffutils", Description: "side-by-side compare"},
	{Name: "nsenter", Path: "/usr/bin/nsenter", Package: "util-linux", Description: "run a command in another namespace (a container's, PID 1's)"},
	{Name: "strace", Path: "/usr/bin/strace", Package: "strace", Description: "trace a process's system calls"},
	{Name: "tcpdump", Path: "/usr/bin/tcpdump", Package: "tcpdump", Description: "capture network traffic (runs as root)"},
	{Name: "socat", Path: "/usr/bin/socat", Package: "socat", Description: "relay and test sockets"},
	{Name: "pv", Path: "/usr/bin/pv", Package: "pv", Description: "progress and throughput of a pipe"},
	{Name: "7z", Path: "/usr/bin/7z", Package: "7zip", Description: "7-Zip archives"},
	{Name: "iotop", Path: "/usr/sbin/iotop", Package: "iotop-c", Description: "disk I/O per process"},
	{Name: "iftop", Path: "/usr/sbin/iftop", Package: "iftop", Description: "network bandwidth per connection"},
	{Name: "screen", Path: "/usr/bin/screen", Package: "screen", Description: "sessions that survive a lost SSH connection"},
	{Name: "mosh-server", Path: "/usr/bin/mosh-server", Package: "mosh", Description: "server side of mosh"},
	{Name: "ping-iputils", Path: "/usr/bin/ping-iputils", Package: "iputils-ping", Description: "a working ping (ZimaOS' own ping is a BusyBox applet that exits 1 without output)"},
}

// Paths the handlers read; tests point them elsewhere.
var (
	packagesFile = "/usr/share/doc/admintools/packages.txt"
	selftest     = "/usr/libexec/admintools/selftest.sh"
	root         = "/"
)

func main() {
	webmod.Run(webmod.Options{
		Name: "admintools", Service: "admintools-web", Binary: "/usr/bin/admintools-web",
		Route: "/admintools", Version: version, API: api,
	})
}

func api(verify func(http.Handler) http.Handler) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("/admintools/tools", verify(http.HandlerFunc(toolsHandler)))
	mux.Handle("/admintools/selftest", verify(http.HandlerFunc(selftestHandler)))
	return mux
}

// packages reads "name version" lines.
func packages() (map[string]string, []string) {
	m := map[string]string{}
	var lines []string
	f, err := os.Open(packagesFile)
	if err != nil {
		return m, nil
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		l := strings.TrimSpace(sc.Text())
		if l == "" {
			continue
		}
		lines = append(lines, l)
		if name, ver, ok := strings.Cut(l, " "); ok {
			m[name] = ver
		}
	}
	return m, lines
}

func toolsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		httpx.MethodNotAllowed(w)
		return
	}
	vers, lines := packages()
	out := make([]Tool, len(tools))
	for i, t := range tools {
		t.Version = vers[t.Package]
		_, err := os.Stat(strings.TrimSuffix(root, "/") + t.Path)
		t.Present = err == nil
		out[i] = t
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"tools": out, "packages": lines, "version": version})
}

// Check is one line of the self-test: "OK   name" or "FAIL name: detail".
type Check struct {
	Name   string `json:"name"`
	OK     bool   `json:"ok"`
	Detail string `json:"detail,omitempty"`
}

var testMu sync.Mutex

func selftestHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		httpx.MethodNotAllowed(w)
		return
	}
	if !testMu.TryLock() {
		httpx.WriteError(w, http.StatusConflict, "busy", "a self-test is already running")
		return
	}
	defer testMu.Unlock()
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Minute)
	defer cancel()
	out, err := exec.CommandContext(ctx, "sh", selftest).CombinedOutput()
	checks := parseChecks(string(out))
	if len(checks) == 0 {
		msg := strings.TrimSpace(string(out))
		if err != nil {
			msg = err.Error() + ": " + msg
		}
		httpx.WriteError(w, http.StatusInternalServerError, "selftest_failed", "the self-test printed no result: "+msg)
		return
	}
	failed := 0
	for _, c := range checks {
		if !c.OK {
			failed++
		}
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"checks": checks, "failed": failed})
}

func parseChecks(out string) []Check {
	var cs []Check
	for _, l := range strings.Split(out, "\n") {
		switch {
		case strings.HasPrefix(l, "OK   "):
			cs = append(cs, Check{Name: strings.TrimSpace(l[5:]), OK: true})
		case strings.HasPrefix(l, "FAIL "):
			name, detail, _ := strings.Cut(strings.TrimSpace(l[5:]), ":")
			cs = append(cs, Check{Name: strings.TrimSpace(name), Detail: strings.TrimSpace(detail)})
		}
	}
	return cs
}
