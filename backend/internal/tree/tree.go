// Package tree finds the axiom tree (the shell's QML and the config
// schema's source) a command works on, and builds the JSON schema from it:
// qml/config/schema/**.yaml → qml/config/json/config.schema.json.
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
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// Paths inside a tree
const (
	// SchemaJSON is the built schema, relative to the QML dir (QMLDir);
	// it is also the binary's embedded copy's key (assets.Read)
	SchemaJSON = "config/json/config.schema.json"
	shellQML   = "shell.qml"
	qmlDir     = "qml"
	// installName is the installed tree's folder under a data dir
	// (~/.local/share/axiom-shell, /usr/share/axiom-shell)
	installName = "axiom-shell"
)

// QMLDir is the tree's QML folder: shell.qml, greeter.qml and config/
// (the schema's YAML source and its built JSON) live under it
func QMLDir(root string) string {
	return filepath.Join(root, qmlDir)
}

// SchemaPath is the built schema's path on disk in the tree at root
func SchemaPath(root string) string {
	return filepath.Join(QMLDir(root), SchemaJSON)
}

// Find is the tree to use: dir when given, else $AXIOM_TREE, else the
// nearest directory up from start that IsTree, else the installed one
// (Installed: a compositor's autostart runs `axiom run` from $HOME).
func Find(dir string, getenv func(string) string, start string) (string, error) {
	if dir == "" {
		dir = getenv("AXIOM_TREE")
	}
	if dir != "" {
		abs, err := filepath.Abs(dir)
		if err != nil {
			return "", err
		}
		if !IsTree(abs) {
			return "", axerr.New(axerr.NotFound, "%s isn't an axiom tree (no qml/shell.qml and qml/config/)", abs)
		}
		return abs, nil
	}
	for d := start; ; d = filepath.Dir(d) {
		if IsTree(d) {
			return d, nil
		}
		if filepath.Dir(d) == d {
			break
		}
	}
	for _, d := range Installed(getenv) {
		if IsTree(d) {
			return d, nil
		}
	}
	return "", axerr.New(axerr.NotFound, "no axiom tree here or above, nor installed (pass --tree)")
}

// Installed is where an installed tree is looked for, in order: the
// user's data folder (a script install, ~/.local/share/axiom-shell), then
// each system one (a package's /usr/share/axiom-shell).
func Installed(getenv func(string) string) []string {
	var out []string
	for _, d := range xdg.SearchDirs(getenv) {
		out = append(out, filepath.Join(d, installName))
	}
	return out
}

// IsTree is whether dir is an axiom tree: it holds qml/shell.qml and
// qml/config/.
func IsTree(dir string) bool {
	if _, err := os.Stat(filepath.Join(QMLDir(dir), shellQML)); err != nil {
		return false
	}
	info, err := os.Stat(filepath.Join(QMLDir(dir), "config"))
	return err == nil && info.IsDir()
}

// BuildSchema assembles the tree's YAML schema source (qml/config/schema/
// and the type folders' schema.yaml) into the JSON schema's bytes. The
// source's paths are relative to the QML dir (QMLDir).
func BuildSchema(dir string) ([]byte, error) {
	qml := QMLDir(dir)
	if _, err := os.Stat(filepath.Join(qml, yamlsrc.IndexFile)); errors.Is(err, fs.ErrNotExist) {
		return nil, axerr.New(axerr.NotFound, "%s has no schema source (%s)", dir, filepath.Join(qmlDir, yamlsrc.IndexFile))
	}
	root, err := yamlsrc.Assemble(os.DirFS(qml))
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
