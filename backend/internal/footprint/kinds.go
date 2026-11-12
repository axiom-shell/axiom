package footprint

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// Absent is the Prior of something that wasn't there.
func Absent() json.RawMessage { return json.RawMessage(`{"absent":true}`) }

// Raw is v as a Prior or Wrote.
func Raw(v any) json.RawMessage {
	data, err := json.Marshal(v)
	if err != nil {
		return nil
	}
	return data
}

// FilePrior is the Prior of a file: absent, or its bytes kept once under
// footprint/prior/<sha256> in the state folder.
type FilePrior struct {
	Absent    bool   `json:"absent,omitempty"`
	BytesPath string `json:"bytesPath,omitempty"`
	Mode      uint32 `json:"mode,omitempty"`
}

// PriorFile is the prior func of a file row for path.
func (l *Ledger) PriorFile(path string) func() (json.RawMessage, error) {
	return func() (json.RawMessage, error) {
		info, err := os.Stat(path)
		if errors.Is(err, fs.ErrNotExist) {
			return Absent(), nil
		}
		if err != nil {
			return nil, err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		sum := sha256.Sum256(data)
		blob := filepath.Join(l.priorDir(), hex.EncodeToString(sum[:]))
		if _, err := os.Stat(blob); err != nil {
			if err := os.MkdirAll(l.priorDir(), 0o700); err != nil {
				return nil, err
			}
			if err := fsx.WriteFile(blob, data, 0o600); err != nil {
				return nil, err
			}
		}
		return Raw(FilePrior{BytesPath: blob, Mode: uint32(info.Mode().Perm())}), nil
	}
}

// missingDirs are the folders of dir's path that don't exist yet, the
// topmost first: what a MkdirAll of dir creates.
func missingDirs(dir string) []string {
	var missing []string
	for d := filepath.Clean(dir); ; d = filepath.Dir(d) {
		if _, err := os.Lstat(d); err == nil || d == filepath.Dir(d) {
			break
		}
		missing = append(missing, d)
	}
	slices.Reverse(missing)
	return missing
}

// BeginDirs records every folder MkdirAll(dir) would make, each its own
// row (an undo takes them out deepest first, each when empty); done marks
// them made. A nil Ledger records nothing.
func (l *Ledger) BeginDirs(dir, owner string) (done func(), err error) {
	if l == nil {
		return func() {}, nil
	}
	var ids []string
	for _, d := range missingDirs(dir) {
		id, err := l.Begin(Row{Kind: KindDir, Target: d, Owner: owner}, PriorAbsent)
		if err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return func() {
		for _, id := range ids {
			l.Done(id, nil)
		}
	}, nil
}

// PriorAbsent is the prior func of something axiom creates.
func PriorAbsent() (json.RawMessage, error) { return Absent(), nil }

func (l *Ledger) priorDir() string { return filepath.Join(l.o.Dirs.State, "footprint", "prior") }

// gcPrior removes the kept bytes no row refers to.
func (l *Ledger) gcPrior(rows []Row) {
	entries, err := os.ReadDir(l.priorDir())
	if err != nil {
		return
	}
	used := map[string]bool{}
	for _, r := range rows {
		var p FilePrior
		if r.Kind == KindFile && json.Unmarshal(r.Prior, &p) == nil && p.BytesPath != "" {
			used[p.BytesPath] = true
		}
	}
	for _, e := range entries {
		if p := filepath.Join(l.priorDir(), e.Name()); !used[p] {
			_ = os.Remove(p)
		}
	}
}

func (l *Ledger) registerGeneric() {
	l.undoers[KindFile], l.checkers[KindFile] = l.undoFile, checkFile
	l.undoers[KindDir], l.checkers[KindDir] = undoDir, checkDir
	l.undoers[KindGSetting], l.checkers[KindGSetting] = l.undoGSetting, l.checkGSetting
	l.undoers[KindMarkedBlock], l.checkers[KindMarkedBlock] = undoMarkedBlock, checkMarkedBlock
	l.undoers[KindRebuild], l.checkers[KindRebuild] = l.undoRebuild, func(context.Context, Row) string { return StatusPresent }
}

// file: deleted, or the bytes it held written back. A file axiom owns
// outright is restored whatever it holds now.
func (l *Ledger) undoFile(_ context.Context, r *Row) (string, string) {
	var p FilePrior
	_ = json.Unmarshal(r.Prior, &p)
	// A file that's the user's once written (Wrote: its sha256) goes only
	// while it's still as written
	var w FileWrote
	if json.Unmarshal(r.Wrote, &w) == nil && w.SHA256 != "" {
		if data, err := os.ReadFile(r.Target); err == nil && sha256Hex(data) != w.SHA256 {
			return OutcomeChanged, "the file was changed since: left as it is"
		}
	}
	if p.BytesPath == "" {
		err := os.Remove(r.Target)
		switch {
		case errors.Is(err, fs.ErrNotExist):
			return OutcomeGone, ""
		case err != nil:
			return OutcomeFailed, err.Error()
		}
		return OutcomeDone, ""
	}
	data, err := os.ReadFile(p.BytesPath)
	if err != nil {
		return OutcomeFailed, "the bytes it held are gone: " + err.Error()
	}
	if err := fsx.WriteFile(r.Target, data, fs.FileMode(p.Mode)); err != nil {
		return OutcomeFailed, err.Error()
	}
	return OutcomeDone, ""
}

func checkFile(_ context.Context, r Row) string {
	if _, err := os.Lstat(r.Target); err != nil {
		return StatusGone
	}
	return StatusPresent
}

// FileWrote is the Wrote of a file row that is the user's once written.
type FileWrote struct {
	SHA256 string `json:"sha256"`
}

// SHA256Of is the Wrote of a file row for data.
func SHA256Of(data []byte) json.RawMessage { return Raw(FileWrote{SHA256: sha256Hex(data)}) }

func sha256Hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// DirWrote on a dir row whose whole tree is axiom's: removed with what's in
// it when MarkerFile holds Marker.
type DirWrote struct {
	MarkerFile string `json:"markerFile"`
	Marker     string `json:"marker"`
}

// dir: removed when empty (or an axiom-marked tree).
func undoDir(_ context.Context, r *Row) (string, string) {
	entries, err := os.ReadDir(r.Target)
	if errors.Is(err, fs.ErrNotExist) {
		return OutcomeGone, ""
	}
	if err != nil {
		return OutcomeFailed, err.Error()
	}
	var w DirWrote
	if len(entries) > 0 && json.Unmarshal(r.Wrote, &w) == nil && w.MarkerFile != "" {
		if data, err := os.ReadFile(filepath.Join(r.Target, w.MarkerFile)); err == nil && strings.Contains(string(data), w.Marker) {
			if err := os.RemoveAll(r.Target); err != nil {
				return OutcomeFailed, err.Error()
			}
			return OutcomeDone, ""
		}
	}
	if len(entries) > 0 {
		return OutcomeChanged, "not empty: left as it is"
	}
	if err := os.Remove(r.Target); err != nil {
		return OutcomeFailed, err.Error()
	}
	return OutcomeDone, ""
}

func checkDir(_ context.Context, r Row) string {
	if _, err := os.Stat(r.Target); err != nil {
		return StatusGone
	}
	return StatusPresent
}

// GSettingPrior is what gsettings held for a key ("get" output) or nothing.
type GSettingPrior struct {
	Absent bool   `json:"absent,omitempty"`
	Value  string `json:"value,omitempty"`
}

// GSettingTarget is the Target of a gsetting row.
func GSettingTarget(schema, key string) string { return schema + " " + key }

// GSettingNormal is a gsettings value as compared: unquoted, without the
// type prefix gsettings prints for an empty array.
func GSettingNormal(v string) string {
	v = strings.TrimSpace(v)
	v = strings.TrimPrefix(v, "@as ")
	if len(v) >= 2 && v[0] == '\'' && v[len(v)-1] == '\'' {
		v = v[1 : len(v)-1]
	}
	return v
}

// PriorGSetting is the prior func of a gsetting row: absent when the key
// has no value of the user's own (an undo then resets it), else what
// gsettings holds now; a key it can't read is an error (nothing is
// recorded or set).
func (l *Ledger) PriorGSetting(ctx context.Context, run func(ctx context.Context, args ...string) (string, error), schema, key string) func() (json.RawMessage, error) {
	return func() (json.RawMessage, error) {
		out, err := run(ctx, "get", schema, key)
		if err != nil {
			return nil, err
		}
		if set, known := l.userValue(ctx, run, schema, key); known && !set {
			return Absent(), nil
		}
		return Raw(GSettingPrior{Value: strings.TrimSpace(out)}), nil
	}
}

// userValue says whether a key has a value of the user's own (not the
// schema's default); known is false when that can't be told: the keyfile
// backend's file is read, dconf is asked (`dconf read`), nothing else.
func (l *Ledger) userValue(ctx context.Context, run func(ctx context.Context, args ...string) (string, error), schema, key string) (set, known bool) {
	if l == nil {
		return false, false
	}
	if l.o.UserValue != nil {
		return l.o.UserValue(ctx, schema, key)
	}
	getenv := l.o.Getenv
	if getenv == nil {
		getenv = os.Getenv
	}
	path := schemaPath(ctx, run, schema)
	if path == "" {
		return false, false
	}
	switch backend := getenv("GSETTINGS_BACKEND"); backend {
	case "keyfile":
		config := getenv("XDG_CONFIG_HOME")
		if !filepath.IsAbs(config) {
			config = filepath.Join(getenv("HOME"), ".config")
		}
		data, err := os.ReadFile(filepath.Join(config, "glib-2.0", "settings", "keyfile"))
		if errors.Is(err, fs.ErrNotExist) {
			return false, true
		}
		if err != nil {
			return false, false
		}
		return keyfileHas(string(data), strings.Trim(path, "/"), key), true
	case "", "dconf":
		if _, err := exec.LookPath("dconf"); err != nil {
			return false, false
		}
		ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		defer cancel()
		out, err := exec.CommandContext(ctx, "dconf", "read", path+key).Output()
		if err != nil {
			return false, false
		}
		return strings.TrimSpace(string(out)) != "", true
	}
	return false, false
}

// schemaPath is the dconf path of a schema ("/org/gnome/desktop/interface/"),
// from gsettings list-schemas --print-paths ("" for none: a relocatable one).
func schemaPath(ctx context.Context, run func(ctx context.Context, args ...string) (string, error), schema string) string {
	out, err := run(ctx, "list-schemas", "--print-paths")
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(out, "\n") {
		if id, path, ok := strings.Cut(strings.TrimSpace(line), " "); ok && id == schema {
			return strings.TrimSpace(path)
		}
	}
	return ""
}

// keyfileHas says whether a glib keyfile (the keyfile backend's) sets key
// in the group.
func keyfileHas(text, group, key string) bool {
	in := false
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "[") {
			in = strings.Trim(line, "[]") == group
			continue
		}
		if k, _, ok := strings.Cut(line, "="); in && ok && strings.TrimSpace(k) == key {
			return true
		}
	}
	return false
}

func (l *Ledger) current(ctx context.Context, r Row) (string, error) {
	schema, key, _ := strings.Cut(r.Target, " ")
	return l.o.GSettings(ctx, "get", schema, key)
}

// gsettingState says how a gsetting row's key stands: gone (nothing of
// axiom's to take out), changed (it's no longer what axiom wrote; a row
// with no Wrote yet, the write maybe never made, is compared with Prior
// instead), or present.
func (l *Ledger) gsettingState(ctx context.Context, r Row) (state, now string, err error) {
	got, err := l.current(ctx, r)
	if err != nil {
		return "", "", err
	}
	now = strings.TrimSpace(got)
	var p GSettingPrior
	_ = json.Unmarshal(r.Prior, &p)
	if r.Wrote == nil {
		if p.Absent {
			schema, key, _ := strings.Cut(r.Target, " ")
			if set, known := l.userValue(ctx, l.o.GSettings, schema, key); known && !set {
				return StatusGone, now, nil
			}
		} else if GSettingNormal(got) == GSettingNormal(p.Value) {
			return StatusGone, now, nil
		}
		return StatusChanged, now, nil
	}
	var wrote string
	_ = json.Unmarshal(r.Wrote, &wrote)
	if GSettingNormal(got) != GSettingNormal(wrote) {
		return StatusChanged, now, nil
	}
	return StatusPresent, now, nil
}

// gsetting: set back to what it held, or reset when nothing was set, only
// while it's still what axiom wrote.
func (l *Ledger) undoGSetting(ctx context.Context, r *Row) (string, string) {
	if l.o.GSettings == nil {
		return OutcomeFailed, "no gsettings"
	}
	state, now, err := l.gsettingState(ctx, *r)
	if err != nil {
		return OutcomeFailed, err.Error()
	}
	switch state {
	case StatusGone:
		return OutcomeGone, ""
	case StatusChanged:
		return OutcomeChanged, "now " + now
	}
	var p GSettingPrior
	_ = json.Unmarshal(r.Prior, &p)
	schema, key, _ := strings.Cut(r.Target, " ")
	args := []string{"set", schema, key, p.Value}
	if p.Absent || p.Value == "" {
		args = []string{"reset", schema, key}
	}
	if _, err := l.o.GSettings(ctx, args...); err != nil {
		return OutcomeFailed, err.Error()
	}
	return OutcomeDone, ""
}

func (l *Ledger) checkGSetting(ctx context.Context, r Row) string {
	if l.o.GSettings == nil {
		return StatusPresent
	}
	state, _, err := l.gsettingState(ctx, r)
	if err != nil {
		return StatusGone
	}
	return state
}

// BlockWrote is the markers of a marked-block row.
type BlockWrote struct {
	Begin string `json:"begin"`
	End   string `json:"end"`
}

// blockRange is [begin, end] of the first marked block in lines.
func blockRange(lines []string, w BlockWrote) (int, int, bool) {
	begin := slices.Index(lines, w.Begin)
	if begin < 0 {
		return 0, 0, false
	}
	end := slices.Index(lines[begin:], w.End)
	if end < 0 {
		return 0, 0, false
	}
	return begin, begin + end, true
}

func readLines(path string) ([]string, bool, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	text := strings.TrimSuffix(string(data), "\n")
	if text == "" {
		return nil, true, nil
	}
	return strings.Split(text, "\n"), true, nil
}

// marked-block: the lines from the begin marker to the end marker.
func undoMarkedBlock(_ context.Context, r *Row) (string, string) {
	var w BlockWrote
	_ = json.Unmarshal(r.Wrote, &w)
	lines, ok, err := readLines(r.Target)
	if err != nil {
		return OutcomeFailed, err.Error()
	}
	begin, end, found := blockRange(lines, w)
	if !ok || !found {
		return OutcomeGone, ""
	}
	lines = slices.Delete(lines, begin, end+1)
	info, _ := os.Stat(r.Target)
	mode := fs.FileMode(0o644)
	if info != nil {
		mode = info.Mode().Perm()
	}
	var buf bytes.Buffer
	for _, l := range lines {
		buf.WriteString(l + "\n")
	}
	if err := fsx.WriteFile(r.Target, buf.Bytes(), mode); err != nil {
		return OutcomeFailed, err.Error()
	}
	return OutcomeDone, ""
}

func checkMarkedBlock(_ context.Context, r Row) string {
	var w BlockWrote
	_ = json.Unmarshal(r.Wrote, &w)
	lines, _, _ := readLines(r.Target)
	if _, _, found := blockRange(lines, w); !found {
		return StatusGone
	}
	return StatusPresent
}

// rebuild: the recorded command (Wrote: its argv) runs once.
func (l *Ledger) undoRebuild(ctx context.Context, r *Row) (string, string) {
	var argv []string
	if json.Unmarshal(r.Wrote, &argv) != nil || len(argv) == 0 {
		return OutcomeGone, ""
	}
	if err := l.o.Run(ctx, argv); err != nil {
		return OutcomeFailed, err.Error()
	}
	return OutcomeDone, ""
}
