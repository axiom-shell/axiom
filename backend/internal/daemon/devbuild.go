package daemon

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/tree"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// The dev build (DevBinary) and what it was built from. Whether it is
// fresh for a tree is a content hash of the files that go into it (the
// ones watchSource rebuilds on, isBuildInput), not git's dirty state: the
// session start execs into a fresh one at once, and builds a stale one
// first.

// minDevHandoff is the lowest buildinfo.Handoff a dev build may have to be
// exec'd: one below it predates dev trees (it would run on the live config,
// and migrate it).
const minDevHandoff = 2

// buildFile records the dev build, under the state folder.
const buildFile = "dev/build.json"

// devBuild is build.json: the tree the dev build was built from and its
// fingerprint then, the tree's commit (for display), and what the binary
// said it is.
type devBuild struct {
	Tree        string    `json:"tree"`
	Fingerprint string    `json:"fingerprint"`
	Commit      string    `json:"commit,omitempty"`
	Dirty       bool      `json:"dirty"`
	Handoff     int       `json:"handoff"`
	Protocol    int       `json:"protocol"`
	At          time.Time `json:"at"`
}

// embeddedInputs are the files outside backend/ the binary embeds (the
// rest of what syncassets copies is built from them or not read by Go),
// relative to the QML dir.
var embeddedInputs = []string{
	"config/json/backend.json",
	"config/json/theme-defaults.json",
}

// isBuildInput: the file at path (absolute) goes into the dev build of the
// tree at treeDir, so an edit to it makes the build stale: the Go source
// and module files under backend/, and the JS and JSON it embeds (tests,
// testdata, hidden files and folders, and the generated copies the build
// itself writes left out), and the embedded files under qml/.
func isBuildInput(treeDir, path string) bool {
	for _, rel := range embeddedInputs {
		if path == filepath.Join(tree.QMLDir(treeDir), rel) {
			return true
		}
	}
	rel, err := filepath.Rel(filepath.Join(treeDir, "backend"), path)
	if err != nil || rel == "." || strings.HasPrefix(rel, "..") {
		return false
	}
	parts := strings.Split(rel, string(filepath.Separator))
	for _, dir := range parts[:len(parts)-1] {
		if skipBuildDir(dir) {
			return false
		}
	}
	if strings.HasPrefix(rel, generatedAssets+string(filepath.Separator)) {
		return false
	}
	base := parts[len(parts)-1]
	if strings.HasPrefix(base, ".") || strings.HasSuffix(base, "_test.go") {
		return false
	}
	switch filepath.Ext(base) {
	case ".go", ".mod", ".sum", ".js", ".json":
		return true
	}
	return false
}

// generatedAssets is where go generate copies the embedded files (under
// backend/): the build's own output, never an input.
const generatedAssets = "internal/assets/data"

// skipBuildDir: a folder (its name) under backend/ holding no build input.
func skipBuildDir(name string) bool {
	return name == "testdata" || (strings.HasPrefix(name, ".") && len(name) > 1)
}

// buildWalkSkip says which folders under backend/ a walk of the build
// inputs (the fingerprint, watchSource) leaves out.
func buildWalkSkip(treeDir string) func(dir string) bool {
	generated := filepath.Join(treeDir, "backend", generatedAssets)
	return func(dir string) bool {
		return dir == generated || skipBuildDir(filepath.Base(dir))
	}
}

// fingerprint is a hash of the tree's build inputs: their paths and
// contents.
func fingerprint(treeDir string) (string, error) {
	h := sha256.New()
	add := func(path string) error {
		rel, _ := filepath.Rel(treeDir, path)
		f, err := os.Open(path)
		if err != nil {
			if os.IsNotExist(err) {
				io.WriteString(h, rel+"\x00missing\x00")
				return nil
			}
			return err
		}
		defer f.Close()
		sum := sha256.New()
		if _, err := io.Copy(sum, f); err != nil {
			return err
		}
		io.WriteString(h, rel+"\x00"+hex.EncodeToString(sum.Sum(nil))+"\x00")
		return nil
	}
	skip := buildWalkSkip(treeDir)
	root := filepath.Join(treeDir, "backend")
	err := filepath.WalkDir(root, func(p string, e fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if e.IsDir() {
			if p != root && skip(p) {
				return filepath.SkipDir
			}
			return nil
		}
		if !e.Type().IsRegular() || !isBuildInput(treeDir, p) {
			return nil
		}
		return add(p)
	})
	if err != nil {
		return "", err
	}
	for _, rel := range embeddedInputs {
		if err := add(filepath.Join(tree.QMLDir(treeDir), rel)); err != nil {
			return "", err
		}
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// readBuild is build.json (false: none, or not readable).
func readBuild(dirs xdg.Dirs) (devBuild, bool) {
	var b devBuild
	data, err := os.ReadFile(dirs.State + buildFile)
	if err != nil || json.Unmarshal(data, &b) != nil {
		return devBuild{}, false
	}
	return b, true
}

// writeBuild records the dev build just made.
func writeBuild(dirs xdg.Dirs, b devBuild) error {
	if err := os.MkdirAll(dirs.State+"dev", 0o700); err != nil {
		return err
	}
	data, _ := json.MarshalIndent(b, "", "  ")
	return fsx.WriteFile(dirs.State+buildFile, append(data, '\n'), 0o600)
}

// buildCheck is whether the dev build is fresh for the dev tree (why not,
// in English, when it isn't), and the build it looked at.
type buildCheck struct {
	Fresh bool
	Why   string
	Build devBuild
	// Gone: the dev tree isn't an axiom tree any more (moved, deleted)
	Gone bool
	// Guarded: the session start already exec'd into this build, and its
	// shell never said hello (the boot guard, devstart.go)
	Guarded bool
}

// buildVerdict says whether build b (nil: none recorded) is fresh for the
// tree at treeDir whose inputs hash to fp, its binary there or not
// (binary). Pure.
func buildVerdict(b *devBuild, treeDir, fp string, binary bool) (bool, string) {
	switch {
	case b == nil:
		return false, "no dev build yet"
	case b.Tree != treeDir:
		return false, "the dev build is of another tree"
	case !binary:
		return false, "the dev build is gone"
	case b.Handoff < minDevHandoff:
		return false, "this tree predates dev trees: merge main"
	case fp == "" || b.Fingerprint != fp:
		return false, "the source changed since the dev build"
	}
	return true, ""
}

// buildFresh checks the dev build against the tree at treeDir.
func buildFresh(dirs xdg.Dirs, treeDir string) buildCheck {
	if !tree.IsTree(treeDir) {
		return buildCheck{Gone: true, Why: "the dev tree " + treeDir + " isn't an axiom tree any more"}
	}
	b, ok := readBuild(dirs)
	var recorded *devBuild
	if ok {
		recorded = &b
	}
	fp, _ := fingerprint(treeDir)
	info, err := os.Stat(DevBinary(dirs))
	binary := err == nil && info.Mode().IsRegular() && info.Mode()&0o111 != 0
	fresh, why := buildVerdict(recorded, treeDir, fp, binary)
	return buildCheck{Fresh: fresh, Why: why, Build: b}
}

// gitState is the dev tree's checkout, for display: its branch ("" when
// detached or not a checkout), commit and whether it has changes.
type gitState struct {
	Branch string
	Commit string
	Dirty  bool
}

// gitInfo reads the tree's checkout: once per switch or build, never
// polled. A tree that isn't a checkout (or git missing) reads as nothing.
func gitInfo(ctx context.Context, treeDir string) gitState {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", "-C", treeDir, "status", "--porcelain=v2", "--branch", "--untracked-files=no")
	cmd.Env = append(os.Environ(), "GIT_OPTIONAL_LOCKS=0")
	out, err := cmd.Output()
	if err != nil {
		return gitState{}
	}
	return parseGitStatus(out)
}

// parseGitStatus reads `git status --porcelain=v2 --branch`. Pure.
func parseGitStatus(out []byte) gitState {
	var st gitState
	for _, line := range bytes.Split(out, []byte("\n")) {
		s := string(line)
		switch {
		case strings.HasPrefix(s, "# branch.oid "):
			if oid := strings.TrimPrefix(s, "# branch.oid "); oid != "(initial)" {
				st.Commit = oid
			}
		case strings.HasPrefix(s, "# branch.head "):
			if head := strings.TrimPrefix(s, "# branch.head "); head != "(detached)" {
				st.Branch = head
			}
		case s != "" && !strings.HasPrefix(s, "#"):
			st.Dirty = true
		}
	}
	return st
}
