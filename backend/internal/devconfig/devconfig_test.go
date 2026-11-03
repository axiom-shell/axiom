package devconfig

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/config"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/migrate/steps"
	"github.com/axiom-shell/axiom/backend/internal/schema"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
	"github.com/axiom-shell/axiom/backend/internal/tree"
)

// devSchema is a small schema of the dev tree's: General.c is a setting
// the install's schema (installSchema) lacks, Idle.enabled a takeover.
func devSchema(t *testing.T) *schema.Schema {
	return schemaOf(t, true)
}

func installSchema(t *testing.T) *schema.Schema {
	return schemaOf(t, false)
}

func schemaOf(t *testing.T, withC bool) *schema.Schema {
	t.Helper()
	c := ""
	if withC {
		c = `, "c": {"type": "boolean", "default": false}`
	}
	text := fmt.Sprintf(`{"type": "object", "additionalProperties": false, "properties": {
		"format": {"type": "integer", "default": 2},
		"version": {"type": "integer", "default": %d},
		"General": {"type": "object", "additionalProperties": false, "properties": {
			"a": {"type": "integer", "default": 1},
			"b": {"type": "string", "default": "x"},
			"list": {"type": "array", "default": [], "items": {"type": "object"}}%s}},
		"Idle": {"type": "object", "additionalProperties": false, "properties": {
			"enabled": {"type": "boolean", "default": false, "x-takeover": true}}}}}`, steps.Current(), c)
	return schema.New(mustParse(t, text))
}

func devPipe(t *testing.T) config.Pipeline { return config.Pipeline{S: devSchema(t)} }

func mustParse(t *testing.T, text string) *jsonx.Object {
	t.Helper()
	obj, err := parse([]byte(text))
	if err != nil {
		t.Fatalf("%s: %v", text, err)
	}
	return obj
}

// cfgText is a format-2 config of version (0: the current one) with body's
// sections.
func cfgText(version int, body string) string {
	if version == 0 {
		version = steps.Current()
	}
	if body != "" {
		body = ", " + body
	}
	return fmt.Sprintf(`{"format": 2, "version": %d%s}`, version, body)
}

func files(t *testing.T) Files {
	dir := t.TempDir()
	return Files{
		Live: filepath.Join(dir, "config", "config.json"),
		Dev:  filepath.Join(dir, "config", "dev", "config.json"),
		Base: filepath.Join(dir, "state", "dev", "base.json"),
	}
}

func put(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
}

// content is a file's text, "" when there is none.
func content(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return ""
	}
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func value(t *testing.T, text string, path ...string) any {
	t.Helper()
	v, _ := config.Lookup(mustParse(t, text), config.Keys(path...))
	return v
}

func TestPrepareSeeds(t *testing.T) {
	t.Parallel()
	live := cfgText(0, `"General": {"a": 5}, "Idle": {"enabled": true}`)
	newer := cfgText(steps.Current()+1, `"General": {"a": 5}, "Idle": {"enabled": true}`)
	newerBad := cfgText(steps.Current()+1, `"Idle": {"enabled": "yes"}`)
	cases := []struct {
		name string
		live string // "" : none
		// dev's values that tell what it was seeded with
		wantA, wantIdle any
		wantCopy        bool   // dev's bytes are live's
		wantNote        string // in the note ("" : no note)
	}{
		{"a copy of live's bytes", live, 5.0, true, true, ""},
		{"no live: the defaults", "", 1.0, false, false, "no live config"},
		{"live newer: the defaults with live's takeovers", newer, 1.0, true, false, "with live's takeover settings"},
		{"live newer, its takeovers don't fit: the defaults", newerBad, 1.0, false, false, "don't fit"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			f := files(t)
			if c.live != "" {
				put(t, f.Live, c.live)
			}
			p, err := Prepare(f, devPipe(t))
			if err != nil {
				t.Fatal(err)
			}
			if !p.Seeded || p.LiveChanged {
				t.Errorf("prepared %+v", p)
			}
			if (c.wantNote == "") != (p.Note == "") || !strings.Contains(p.Note, c.wantNote) {
				t.Errorf("note %q, want %q", p.Note, c.wantNote)
			}
			dev := content(t, f.Dev)
			if c.wantCopy && dev != c.live {
				t.Errorf("dev %s, want live's bytes", dev)
			}
			if a := value(t, dev, "General", "a"); a != c.wantA {
				t.Errorf("General.a %v, want %v", a, c.wantA)
			}
			if idle := value(t, dev, "Idle", "enabled"); idle != c.wantIdle {
				t.Errorf("Idle.enabled %v, want %v", idle, c.wantIdle)
			}
			if base := content(t, f.Base); base != c.live {
				t.Errorf("base %q, want live's bytes %q", base, c.live)
			}
			if info, err := os.Stat(f.Dev); err != nil || info.Mode().Perm() != 0o600 {
				t.Errorf("dev config %v %v", info, err)
			}
		})
	}
}

func TestPrepareTakeoverPatch(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name, dev, live string
		wantPatched     []string
		wantIdle        any
		wantNote        string
	}{
		{"live's value goes in", cfgText(0, `"General": {"a": 7}, "Idle": {"enabled": false}`), cfgText(0, `"Idle": {"enabled": true}`), []string{"Idle.enabled"}, true, ""},
		{"made where dev lacks the section", cfgText(0, `"General": {"a": 7}`), cfgText(0, `"Idle": {"enabled": true}`), []string{"Idle.enabled"}, true, ""},
		{"a default isn't a difference", cfgText(0, `"General": {"a": 7}`), cfgText(0, `"Idle": {"enabled": false}`), nil, nil, ""},
		{"equal: untouched", cfgText(0, `"Idle": {"enabled": true}`), cfgText(0, `"Idle": {"enabled": true}`), nil, true, ""},
		{"live's doesn't fit dev's schema", cfgText(0, `"Idle": {"enabled": false}`), cfgText(0, `"Idle": {"enabled": "yes"}`), nil, false, "don't fit"},
		{"older live, in dev's shape", cfgText(0, `"Idle": {"enabled": false}`), cfgText(steps.Current()-1, `"Idle": {"enabled": true}`), []string{"Idle.enabled"}, true, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			f := files(t)
			put(t, f.Live, c.live)
			put(t, f.Base, c.live)
			put(t, f.Dev, c.dev)
			p, err := Prepare(f, devPipe(t))
			if err != nil {
				t.Fatal(err)
			}
			if p.Seeded || strings.Join(p.Patched, ",") != strings.Join(c.wantPatched, ",") || !strings.Contains(p.Note, c.wantNote) {
				t.Errorf("prepared %+v", p)
			}
			dev := content(t, f.Dev)
			if len(c.wantPatched) == 0 && dev != c.dev {
				t.Errorf("dev rewritten: %s", dev)
			}
			if idle := value(t, dev, "Idle", "enabled"); idle != c.wantIdle {
				t.Errorf("Idle.enabled %v, want %v", idle, c.wantIdle)
			}
			// Nothing but the takeover changes in dev
			if a := value(t, dev, "General", "a"); a != value(t, c.dev, "General", "a") {
				t.Errorf("General.a %v", a)
			}
			if got := content(t, f.Live); got != c.live {
				t.Errorf("live written: %s", got)
			}
		})
	}
}

func TestPrepareKeepsDevsOwnKeys(t *testing.T) {
	t.Parallel()
	f := files(t)
	put(t, f.Live, cfgText(0, `"Idle": {"enabled": true}`))
	put(t, f.Dev, cfgText(0, `"Idle": {"enabled": false}, "Unknown": {"k": 1}`))
	if _, err := Prepare(f, devPipe(t)); err != nil {
		t.Fatal(err)
	}
	if value(t, content(t, f.Dev), "Unknown", "k") != 1.0 {
		t.Errorf("dev's raw keys lost: %s", content(t, f.Dev))
	}
}

func TestPrepareLiveChanged(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name, live, base string // base "": none yet
		want             bool
		wantBase         string // the base after ("": live)
	}{
		{"no base yet: live is the base", cfgText(0, `"General": {"a": 3}`), "", false, ""},
		{"the same bytes", cfgText(0, `"General": {"a": 3}`), cfgText(0, `"General": {"a": 3}`), false, ""},
		{"a default spelled out isn't a change", cfgText(0, `"General": {"a": 1}`), cfgText(0, ``), false, cfgText(0, ``)},
		{"live migrated since isn't a change", cfgText(0, `"General": {"a": 3}`), cfgText(steps.Current()-1, `"General": {"a": 3}`), false, cfgText(steps.Current()-1, `"General": {"a": 3}`)},
		{"a setting changed", cfgText(0, `"General": {"a": 9}`), cfgText(0, `"General": {"a": 3}`), true, cfgText(0, `"General": {"a": 3}`)},
		{"live doesn't load: the bytes decide", `{"format": 2}`, cfgText(0, ``), true, cfgText(0, ``)},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			f := files(t)
			put(t, f.Live, c.live)
			put(t, f.Dev, cfgText(0, ``))
			if c.base != "" {
				put(t, f.Base, c.base)
			}
			p, err := Prepare(f, devPipe(t))
			if err != nil {
				t.Fatal(err)
			}
			if p.LiveChanged != c.want {
				t.Errorf("liveChanged %v, want %v", p.LiveChanged, c.want)
			}
			want := c.wantBase
			if want == "" {
				want = c.live
			}
			if got := content(t, f.Base); got != want {
				t.Errorf("base %s, want %s", got, want)
			}
		})
	}
}

func TestPrepareWaitsForNoStore(t *testing.T) {
	t.Parallel()
	f := files(t)
	put(t, f.Dev, cfgText(0, ``))
	lock, err := fsx.TryLock(f.Dev + ".lock")
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Release()
	if _, err := Prepare(f, devPipe(t)); axerr.KindOf(err) != axerr.Running {
		t.Errorf("prepared under a held lock: %v", err)
	}
}

func TestRows(t *testing.T) {
	t.Parallel()
	base := mustParse(t, cfgText(0, `"General": {"a": 1, "b": "x", "c": false, "list": []}, "Extra": {"k": 1}`))
	live := mustParse(t, cfgText(0, `"General": {"a": 2, "b": "y", "c": false, "list": []}, "Extra": {"k": 1}`))
	dev := mustParse(t, cfgText(steps.Current()+1, `"General": {"a": 1, "b": "z", "c": true, "list": [{"id": "q"}]}`))
	type want struct {
		side            string
		devOnly         bool
		hasDev, hasLive bool
		devVal, liveVal any
	}
	wants := map[string]want{
		"General.a":    {SideLive, false, true, true, 1.0, 2.0},
		"General.b":    {SideBoth, false, true, true, "z", "y"},
		"General.c":    {SideDev, true, true, true, true, false},
		"General.list": {SideDev, false, true, true, nil, nil},
		"Extra":        {SideDev, true, false, true, nil, nil},
	}
	rows := Rows(base, live, dev, installSchema(t))
	if len(rows) != len(wants) {
		t.Errorf("%d rows, want %d: %+v", len(rows), len(wants), rows)
	}
	for _, r := range rows {
		w, ok := wants[r.Path.String()]
		if !ok {
			t.Errorf("unexpected row %s (the version is never a row)", r.Path)
			continue
		}
		if r.Side != w.side || r.DevOnly != w.devOnly || r.HasDev != w.hasDev || r.HasLive != w.hasLive {
			t.Errorf("%s: %+v, want %+v", r.Path, r, w)
		}
		if w.devVal != nil && (r.Dev != w.devVal || r.Live != w.liveVal) {
			t.Errorf("%s: values %v / %v, want %v / %v", r.Path, r.Dev, r.Live, w.devVal, w.liveVal)
		}
	}
	// Without a base, every row changed on both sides
	for _, r := range Rows(nil, live, dev, installSchema(t)) {
		if r.Side != SideBoth {
			t.Errorf("no base: %s is %s", r.Path, r.Side)
		}
	}
}

func TestRowJSON(t *testing.T) {
	t.Parallel()
	r := Row{Path: config.Keys("Extra"), Side: SideDev, Live: mustParse(t, `{"k": 1}`), HasLive: true, DevOnly: true}
	got, err := json.Marshal(r)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != `{"devOnly":true,"live":{"k":1},"path":["Extra"],"side":"dev"}` {
		t.Errorf("got %s", got)
	}
}

func TestMerge(t *testing.T) {
	t.Parallel()
	base := cfgText(0, `"General": {"a": 1, "b": "x", "list": []}, "Extra": {"k": 1}`)
	cases := []struct {
		name, base, live, dev string
		want                  string // the ops, as JSON
	}{
		{"live's change comes over", base, cfgText(0, `"General": {"a": 2, "b": "x", "list": []}, "Extra": {"k": 1}`), base,
			`[{"base":1,"op":"set","path":["General","a"],"value":2}]`},
		{"dev's change stays", base, base, cfgText(0, `"General": {"a": 3, "b": "x", "list": []}, "Extra": {"k": 1}`), `null`},
		{"both changed: a conflict, left alone", base,
			cfgText(0, `"General": {"a": 2, "b": "y", "list": []}, "Extra": {"k": 1}`),
			cfgText(0, `"General": {"a": 3, "b": "x", "list": []}, "Extra": {"k": 1}`),
			`[{"base":"x","op":"set","path":["General","b"],"value":"y"}]`},
		{"a list whole", base, cfgText(0, `"General": {"a": 1, "b": "x", "list": [{"id": "p"}]}, "Extra": {"k": 1}`), base,
			`[{"base":[],"op":"set","path":["General","list"],"value":[{"id":"p"}]}]`},
		{"a key live dropped", base, cfgText(0, `"General": {"a": 1, "b": "x", "list": []}`), base,
			`[{"base":{"k":1},"op":"delete","path":["Extra"]}]`},
		{"a key live added", base, cfgText(0, `"General": {"a": 1, "b": "x", "list": []}, "Extra": {"k": 1}, "New": {"n": 1}`), base,
			`[{"op":"set","path":["New"],"value":{"n":1}}]`},
		{"never the version", base, cfgText(steps.Current()-1, `"General": {"a": 1, "b": "x", "list": []}, "Extra": {"k": 1}`), base, `null`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			dev := mustParse(t, c.dev)
			ops := Merge(mustParse(t, c.base), mustParse(t, c.live), dev)
			got, _ := json.Marshal(ops)
			if string(got) != c.want {
				t.Fatalf("got %s\nwant %s", got, c.want)
			}
			if err := config.ApplyOps(dev, ops); err != nil {
				t.Errorf("the ops don't apply to dev: %v", err)
			}
		})
	}
	if ops := Merge(nil, mustParse(t, base), mustParse(t, cfgText(0, ``))); ops != nil {
		t.Errorf("merged without a base: %v", ops)
	}
}

func TestWriteLive(t *testing.T) {
	t.Parallel()
	// An old version, defaults missing: as written, never loaded
	live := `{"format": 2, "version": 3, "General": {"a": 1}}`
	baseText := `{"format": 2, "version": 3, "General": {"a": 1, "b": "old"}}`
	set := func(value any, keys ...string) []config.Op {
		return []config.Op{config.SetValue(config.Keys(keys...), value)}
	}
	cases := []struct {
		name     string
		ops      []config.Op
		noBase   bool
		holdLock bool
		noLive   bool
		kind     axerr.Kind
		wantLive string // after, compact
		wantBase string
	}{
		{name: "a setting", ops: set(4.0, "General", "a"),
			wantLive: `{"format":2,"version":3,"General":{"a":4}}`, wantBase: `{"format":2,"version":3,"General":{"a":4,"b":"old"}}`},
		{name: "a section made", ops: set(true, "Idle", "enabled"),
			wantLive: `{"format":2,"version":3,"General":{"a":1},"Idle":{"enabled":true}}`, wantBase: `{"format":2,"version":3,"General":{"a":1,"b":"old"},"Idle":{"enabled":true}}`},
		{name: "a delete", ops: []config.Op{{Op: "delete", Path: config.Keys("General", "a")}},
			wantLive: `{"format":2,"version":3,"General":{}}`, wantBase: `{"format":2,"version":3,"General":{"b":"old"}}`},
		{name: "no base yet: live's new bytes", ops: set(4.0, "General", "a"), noBase: true,
			wantLive: `{"format":2,"version":3,"General":{"a":4}}`, wantBase: `{"format":2,"version":3,"General":{"a":4}}`},
		{name: "the version is live's own", ops: set(99.0, "version"), kind: axerr.BadRequest},
		{name: "the format too", ops: []config.Op{{Op: "delete", Path: config.Keys("format")}}, kind: axerr.BadRequest},
		{name: "a dev-only setting", ops: set(true, "General", "c"), kind: axerr.InvalidConfig},
		{name: "an invalid value", ops: set("four", "General", "a"), kind: axerr.InvalidConfig},
		{name: "an op that fails", ops: []config.Op{config.SetValue(config.Keys("General", "a"), 4.0).WithBase(2.0)}, kind: axerr.Conflict},
		{name: "a store has live open", ops: set(4.0, "General", "a"), holdLock: true, kind: axerr.Running},
		{name: "no live config", ops: set(4.0, "General", "a"), noLive: true, kind: axerr.NotFound},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			f := files(t)
			if !c.noLive {
				put(t, f.Live, live)
			}
			if !c.noBase {
				put(t, f.Base, baseText)
			}
			if c.holdLock {
				os.MkdirAll(filepath.Dir(f.Live), 0o700)
				lock, err := fsx.TryLock(f.Live + ".lock")
				if err != nil {
					t.Fatal(err)
				}
				defer lock.Release()
			}
			err := WriteLive(f.Live, f.Base, c.ops, installSchema(t))
			if c.kind != "" {
				if axerr.KindOf(err) != c.kind {
					t.Fatalf("err %v, want %s", err, c.kind)
				}
				if !c.noLive && content(t, f.Live) != live {
					t.Errorf("live changed on a refusal: %s", content(t, f.Live))
				}
				if !c.noBase && content(t, f.Base) != baseText {
					t.Errorf("base changed on a refusal: %s", content(t, f.Base))
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if got := compact(t, content(t, f.Live)); got != c.wantLive {
				t.Errorf("live %s\nwant %s", got, c.wantLive)
			}
			if got := compact(t, content(t, f.Base)); got != c.wantBase {
				t.Errorf("base %s\nwant %s", got, c.wantBase)
			}
		})
	}
}

// WriteDev and ReplaceDev write the dev config's file as WriteLive does
// live's: raw, checked against the dev schema, its version its own, ops'
// bases not held against defaults the file leaves out, the base untouched.
func TestWriteDev(t *testing.T) {
	t.Parallel()
	f := files(t)
	dev := `{"format": 2, "version": 3, "General": {"a": 1}}`
	put(t, f.Dev, dev)
	put(t, f.Base, dev)
	ops := []config.Op{
		config.SetValue(config.Keys("General", "c"), true),
		config.SetValue(config.Keys("General", "b"), "y").WithBase("x"), // "x" is b's default, not in the file
		{Op: "delete", Path: config.Keys("Idle", "enabled")},            // not in the file either
	}
	if err := WriteDev(f.Dev, ops, devSchema(t)); err != nil {
		t.Fatal(err)
	}
	if got := compact(t, content(t, f.Dev)); got != `{"format":2,"version":3,"General":{"a":1,"c":true,"b":"y"}}` {
		t.Errorf("dev %s", got)
	}
	if content(t, f.Base) != dev {
		t.Errorf("base changed: %s", content(t, f.Base))
	}
	if err := WriteDev(f.Dev, []config.Op{config.SetValue(config.Keys("General", "a"), "four")}, devSchema(t)); axerr.KindOf(err) != axerr.InvalidConfig {
		t.Errorf("an invalid value: %v", err)
	}
	if err := WriteDev(f.Dev, []config.Op{config.SetValue(config.Keys("version"), 9.0)}, devSchema(t)); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("dev's version: %v", err)
	}

	live := mustParse(t, cfgText(0, `"General": {"a": 7, "b": "z"}`))
	if err := ReplaceDev(f.Dev, live, devSchema(t)); err != nil {
		t.Fatal(err)
	}
	if got := compact(t, content(t, f.Dev)); got != `{"format":2,"version":3,"General":{"a":7,"b":"z"}}` {
		t.Errorf("dev after the replace %s", got)
	}

	lock, err := fsx.TryLock(f.Dev + ".lock")
	if err != nil {
		t.Fatal(err)
	}
	defer lock.Release()
	if err := ReplaceDev(f.Dev, live, devSchema(t)); axerr.KindOf(err) != axerr.Running {
		t.Errorf("a store has dev open: %v", err)
	}
}

func compact(t *testing.T, text string) string {
	return string(jsonx.MarshalCompact(mustParse(t, text)))
}

// The real schema, end to end: a dev config seeded from live, changed,
// diffed, and the change written back without touching live's version.
func TestRealSchema(t *testing.T) {
	t.Parallel()
	data, err := tree.BuildSchema(testkit.RepoRoot())
	if err != nil {
		t.Fatal(err)
	}
	pipe := config.Pipeline{S: schema.New(mustParse(t, string(data)))}
	f := files(t)
	put(t, f.Live, string(jsonx.Marshal(pipe.Defaults())))
	if p, err := Prepare(f, pipe); err != nil || !p.Seeded || p.Note != "" {
		t.Fatalf("prepared %+v, %v", p, err)
	}
	dev, err := InShape(pipe, []byte(content(t, f.Dev)))
	if err != nil {
		t.Fatal(err)
	}
	path := config.Keys("Idle", "dim", "timeout")
	if err := config.ApplyOps(dev, []config.Op{config.SetValue(path, 123.0)}); err != nil {
		t.Fatal(err)
	}
	live, _ := InShape(pipe, []byte(content(t, f.Live)))
	base, _ := InShape(pipe, []byte(content(t, f.Base)))
	rows := Rows(base, live, dev, pipe.Schema())
	if len(rows) != 1 || rows[0].Path.String() != "Idle.dim.timeout" || rows[0].Side != SideDev || rows[0].DevOnly {
		t.Fatalf("rows %+v", rows)
	}
	if err := WriteLive(f.Live, f.Base, []config.Op{config.SetValue(rows[0].Path, rows[0].Dev)}, pipe.Schema()); err != nil {
		t.Fatal(err)
	}
	written := mustParse(t, content(t, f.Live))
	if v, _ := config.Lookup(written, path); v != 123.0 || written.Value("version") != float64(steps.Current()) {
		t.Errorf("live after: timeout %v, version %v", v, written.Value("version"))
	}
	if p, err := Prepare(f, pipe); err != nil || p.LiveChanged {
		t.Errorf("our own write taken for live's: %+v %v", p, err)
	}
}
