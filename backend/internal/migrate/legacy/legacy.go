// Package legacy upgrades a format-1 config (versions 1 to 75, from before
// the axiom binary owned the config) to version 75 by running the shell's
// own frozen migration code (legacy.js) in an embedded JS engine. The code
// is frozen, so running it is exact where a port could drift; the shared
// fixtures (legacy and corpus suites) check it against the shell's engine.
// Pure: the engine has no I/O, timers or host access.
package legacy

import (
	_ "embed"
	"fmt"
	"sync"
	"time"

	"github.com/dop251/goja"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

//go:embed legacy.js
var source string

// The schema format 1 ended at (version 75), frozen with the migrations:
// a format-1 file is loaded against it before it's converted to format 2.
//
//go:embed schema-v75.json
var schemaV75 []byte

// Schema is the frozen version-75 schema, parsed anew for each caller.
func Schema() *jsonx.Object {
	v, err := jsonx.Unmarshal(schemaV75)
	if err != nil {
		panic(err) // embedded and hash-checked by the tests
	}
	return v.(*jsonx.Object)
}

// LastVersion is the last format-1 version: legacy.js's currentVersion.
const LastVersion = 75

// Result is migrate()'s: the upgraded config, what was done (English, for
// the log), and whether anything was.
type Result struct {
	Config   *jsonx.Object
	Changes  []string
	Migrated bool
}

// timeout bounds one run: migrating a config takes milliseconds, so this
// only stops a pathological input from hanging the caller
const timeout = 10 * time.Second

var program = sync.OnceValues(func() (*goja.Program, error) {
	return goja.Compile("legacy.js", source+"\n;(function (text) { return JSON.stringify(ConfigMigration.migrate(JSON.parse(text))); })", true)
})

// Migrate runs ConfigMigration.migrate on config (not modified). A config
// that isn't an object is treated as the JS does (`config ?? {}` then
// property reads).
func Migrate(config any) (Result, error) {
	prog, err := program()
	if err != nil {
		return Result{}, fmt.Errorf("legacy migrations don't compile: %w", err)
	}
	vm := goja.New()
	timer := time.AfterFunc(timeout, func() { vm.Interrupt("legacy migration timed out") })
	defer timer.Stop()

	fn, err := vm.RunProgram(prog)
	if err != nil {
		return Result{}, fmt.Errorf("legacy migrations: %w", err)
	}
	call, ok := goja.AssertFunction(fn)
	if !ok {
		return Result{}, fmt.Errorf("legacy migrations: no entry point")
	}
	out, err := call(goja.Undefined(), vm.ToValue(string(jsonx.MarshalCompact(config))))
	if err != nil {
		return Result{}, fmt.Errorf("migrating the config: %w", err)
	}
	parsed, err := jsonx.Unmarshal([]byte(out.String()))
	if err != nil {
		return Result{}, fmt.Errorf("legacy migrations returned bad JSON: %w", err)
	}
	obj, _ := parsed.(*jsonx.Object)
	res := Result{Migrated: obj.Value("migrated") == true}
	res.Config, _ = obj.Value("config").(*jsonx.Object)
	if res.Config == nil {
		return Result{}, fmt.Errorf("legacy migrations returned no config")
	}
	if changes, ok := obj.Value("changes").(*jsonx.Array); ok {
		for _, c := range changes.Items {
			res.Changes = append(res.Changes, jsonx.ToString(c))
		}
	}
	return res, nil
}
