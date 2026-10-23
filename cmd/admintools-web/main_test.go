package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func open(next http.Handler) http.Handler { return next }

func call(t *testing.T, method, path string) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	w := httptest.NewRecorder()
	api(open).ServeHTTP(w, httptest.NewRequest(method, path, nil))
	var body map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &body)
	return w, body
}

func TestToolsReadVersionsAndPresence(t *testing.T) {
	dir := t.TempDir()
	packagesFile = filepath.Join(dir, "packages.txt")
	root = dir
	if err := os.WriteFile(packagesFile, []byte("strace 6.13+ds-1\ndiffutils 1:3.10-4\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "usr/bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "usr/bin/strace"), nil, 0o755); err != nil {
		t.Fatal(err)
	}
	w, body := call(t, "GET", "/admintools/tools")
	if w.Code != 200 {
		t.Fatalf("status %d: %s", w.Code, w.Body)
	}
	found := map[string]map[string]any{}
	for _, x := range body["tools"].([]any) {
		m := x.(map[string]any)
		found[m["name"].(string)] = m
	}
	if s := found["strace"]; s["version"] != "6.13+ds-1" || s["present"] != true {
		t.Errorf("strace: %v", s)
	}
	if d := found["diff"]; d["version"] != "1:3.10-4" || d["present"] != false {
		t.Errorf("diff (version known, file absent): %v", d)
	}
	if len(found) != len(tools) {
		t.Errorf("%d tools listed, want %d", len(found), len(tools))
	}
}

func TestSelftestParsesTheScriptsLines(t *testing.T) {
	dir := t.TempDir()
	selftest = filepath.Join(dir, "selftest.sh")
	script := "echo 'OK   diff'\necho 'FAIL tcpdump: tcpdump: Couldn'\"'\"'t find user'\necho 'admintools host-test: 1 OK, 1 FAIL'\nexit 1\n"
	if err := os.WriteFile(selftest, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	w, body := call(t, "POST", "/admintools/selftest")
	if w.Code != 200 {
		t.Fatalf("status %d: %s", w.Code, w.Body)
	}
	if body["failed"] != float64(1) {
		t.Errorf("failed = %v, want 1", body["failed"])
	}
	cs := body["checks"].([]any)
	if len(cs) != 2 {
		t.Fatalf("checks %v", cs)
	}
	f := cs[1].(map[string]any)
	if f["name"] != "tcpdump" || f["ok"] != false || f["detail"] != "tcpdump: Couldn't find user" {
		t.Errorf("fail line parsed as %v", f)
	}
}

// A script that prints nothing must not look like an empty, passing test.
func TestSelftestWithoutResultIsAnError(t *testing.T) {
	dir := t.TempDir()
	selftest = filepath.Join(dir, "selftest.sh")
	if err := os.WriteFile(selftest, []byte("echo broken >&2; exit 3\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	w, _ := call(t, "POST", "/admintools/selftest")
	if w.Code != http.StatusInternalServerError {
		t.Fatalf("status %d, want 500: %s", w.Code, w.Body)
	}
}

func TestMethods(t *testing.T) {
	if w, _ := call(t, "POST", "/admintools/tools"); w.Code != http.StatusMethodNotAllowed {
		t.Errorf("POST tools: %d", w.Code)
	}
	if w, _ := call(t, "GET", "/admintools/selftest"); w.Code != http.StatusMethodNotAllowed {
		t.Errorf("GET selftest: %d", w.Code)
	}
}
