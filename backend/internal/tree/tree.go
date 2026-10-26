// Package tree finds the axiom tree (the shell's QML and the config
// schema's source) a command works on, and builds the JSON schema from it:
// config/schema/**.yaml → config/json/config.schema.json.
//
// It is the disk side of schema/yamlsrc, which stays pure: tree finds the
// tree, hands yamlsrc the files (os.DirFS) and reports yamlsrc's problems
// as one axerr.Error. What the YAML means, how the files join and what
// they may hold is yamlsrc's alone.
package tree

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/schema/yamlsrc"
)

// Paths inside a tree
const (
	SchemaJSON = "config/json/config.schema.json"
	shellQML   = "shell.qml"
)

// Find is the tree to use: dir when given, else $AXIOM_TREE, else the
// nearest directory up from start holding shell.qml and config/, else the
// installed one, where a clone or package puts it (a compositor's autostart runs
// `axiom run` from $HOME).
func Find(dir string, getenv func(string) string, start string) (string, error) {
	if dir == "" {
		dir = getenv("AXIOM_TREE")
	}
	if dir != "" {
		abs, err := filepath.Abs(dir)
		if err != nil {
			return "", err
		}
		if !isTree(abs) {
			return "", axerr.New(axerr.NotFound, "%s isn't an axiom tree (no shell.qml and config/)", abs)
		}
		return abs, nil
	}
	for d := start; ; d = filepath.Dir(d) {
		if isTree(d) {
			return d, nil
		}
		if filepath.Dir(d) == d {
			break
		}
	}
	for _, d := range Installed(getenv) {
		if isTree(d) {
			return d, nil
		}
	}
	return "", axerr.New(axerr.NotFound, "no axiom tree here or above, nor installed (pass --tree)")
}

// Installed is where an installed tree is looked for, in order, as
// quickshell finds `-c axiom`: the user's config folder (a clone), then
// each system one (a package links /etc/xdg/quickshell/axiom).
func Installed(getenv func(string) string) []string {
	var out []string
	home := getenv("XDG_CONFIG_HOME")
	if home == "" && getenv("HOME") != "" {
		home = filepath.Join(getenv("HOME"), ".config")
	}
	if home != "" {
		out = append(out, filepath.Join(home, "quickshell", "axiom"))
	}
	dirs := getenv("XDG_CONFIG_DIRS")
	if dirs == "" {
		dirs = "/etc/xdg"
	}
	for _, d := range filepath.SplitList(dirs) {
		if filepath.IsAbs(d) {
			out = append(out, filepath.Join(d, "quickshell", "axiom"))
		}
	}
	return out
}

func isTree(dir string) bool {
	if _, err := os.Stat(filepath.Join(dir, shellQML)); err != nil {
		return false
	}
	info, err := os.Stat(filepath.Join(dir, "config"))
	return err == nil && info.IsDir()
}

// BuildSchema assembles the tree's YAML schema source (config/schema/ and
// the type folders' schema.yaml) into the JSON schema's bytes.
func BuildSchema(dir string) ([]byte, error) {
	if _, err := os.Stat(filepath.Join(dir, yamlsrc.IndexFile)); errors.Is(err, fs.ErrNotExist) {
		return nil, axerr.New(axerr.NotFound, "%s has no schema source (%s)", dir, yamlsrc.IndexFile)
	}
	root, err := yamlsrc.Assemble(os.DirFS(dir))
	if err != nil {
		var errs yamlsrc.Errors
		if errors.As(err, &errs) {
			e := &axerr.Error{Kind: axerr.InvalidConfig, Message: fmt.Sprintf("the schema source has %d problems", len(errs))}
			for _, x := range errs {
				where := x.File
				if x.Line > 0 {
					where = fmt.Sprintf("%s:%d:%d", where, x.Line, x.Column)
				}
				e.Issues = append(e.Issues, axerr.Issue{Path: where, Message: x.Msg})
			}
			return nil, e
		}
		return nil, axerr.Wrap(axerr.InvalidConfig, err, "the schema source")
	}
	return jsonx.Marshal(root), nil
}
