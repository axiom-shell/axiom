// Command syncassets writes the repo files the binary embeds into
// internal/assets/data, because go:embed can't reach outside the module
// directory: copies of the sources, and the config schema built from its
// YAML source (here rather than by `axiom schema build`, which can't
// compile before its embedded copy exists). It writes the tree's own
// config/json/config.schema.json too, the one the shell and the checks
// read, so building it compiles this small program, not the whole binary.
// Run through `go generate` (scripts/generate.sh); data/ is gitignored.
package main

import (
	"bytes"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/tree"
)

// The repo paths (relative to the repo root) copied, keeping their layout
// under data/. A directory is copied whole.
var sources = []string{
	"config/json/backend.json",
	"config/json/theme-defaults.json",
}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: syncassets <repo root> <data dir>")
		os.Exit(2)
	}
	if err := sync(os.Args[1], os.Args[2]); err != nil {
		fmt.Fprintln(os.Stderr, "syncassets:", err)
		os.Exit(1)
	}
}

func sync(root, out string) error {
	schema, err := tree.BuildSchema(root)
	if err != nil {
		return err
	}
	want := map[string][]byte{tree.SchemaJSON: schema}
	for _, src := range sources {
		full := filepath.Join(root, src)
		err := filepath.WalkDir(full, func(path string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return err
			}
			data, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			rel, err := filepath.Rel(root, path)
			if err != nil {
				return err
			}
			want[filepath.ToSlash(rel)] = data
			return nil
		})
		if err != nil {
			return err
		}
	}

	// Drop copies whose source is gone, so a removed file doesn't linger
	// embedded
	_ = filepath.WalkDir(out, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(out, path)
		if _, ok := want[filepath.ToSlash(rel)]; !ok {
			return os.Remove(path)
		}
		return nil
	})

	names := make([]string, 0, len(want))
	for name := range want {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		dst := filepath.Join(out, filepath.FromSlash(name))
		if old, err := os.ReadFile(dst); err == nil && bytes.Equal(old, want[name]) {
			continue
		}
		if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(dst, want[name], 0o644); err != nil {
			return err
		}
	}

	// The tree's copy by rename, as `axiom schema build` writes it: the
	// shell may be reading it
	own := filepath.Join(root, tree.SchemaJSON)
	if old, err := os.ReadFile(own); err == nil && bytes.Equal(old, schema) {
		return nil
	}
	return fsx.WriteFile(own, schema, 0o644)
}
