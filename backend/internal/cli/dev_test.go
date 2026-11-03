package cli

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// With no axiom running, `axiom dev options` and `dev set` save the
// choice for its next start (install.sh asks before the first one)
func TestDevSetOffline(t *testing.T) {
	home, runtime := t.TempDir(), t.TempDir()
	env := map[string]string{"HOME": home, "XDG_RUNTIME_DIR": runtime}
	var out, errOut bytes.Buffer
	e := &Env{Stdout: &out, Stderr: &errOut, Getenv: func(k string) string { return env[k] }}
	if code := Run(context.Background(), Root(), []string{"dev", "options", "on"}, e); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	if !strings.Contains(out.String(), "no axiom is running") {
		t.Errorf("said %q", out.String())
	}
	data, err := os.ReadFile(filepath.Join(home, ".local", "state", "axiom", "dev.json"))
	if err != nil || !strings.Contains(string(data), `"options":true`) {
		t.Errorf("dev.json %s (%v)", data, err)
	}
	out.Reset()
	errOut.Reset()
	if code := Run(context.Background(), Root(), []string{"dev", "on"}, e); code == 0 {
		t.Errorf("dev on with no axiom running: exit 0, %s", out.String())
	}
}
