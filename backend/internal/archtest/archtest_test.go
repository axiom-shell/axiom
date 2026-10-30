// Package archtest checks the structure rules of backend/AGENTS.md on the
// source. Every package is classified into a tier, and imports only point
// down the tiers: the pure packages (the Go side of components/methods/) do
// no I/O and import only each other, the edge packages do the I/O, and only
// the daemon and the command line wire them together. Every package has a
// doc comment (marking the pure ones as such), no init(), and no
// package-level state.
package archtest

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"testing"
)

const module = "github.com/axiom-shell/axiom/backend/"

// The tiers, lowest first: a package imports only packages of its own tier
// or a lower one
const (
	tierPure   = iota // no I/O (backend/AGENTS.md › Rules)
	tierEdge          // files, sockets, processes, buses, compositors
	tierDaemon        // the daemon, wiring the edge packages together
	tierCLI           // the command line, which also starts the daemon
	tierMain          // cmd/ and tools/: programs
)

var tierNames = []string{"pure", "edge", "daemon", "cli", "main"}

// Every package, by directory under backend/ (a trailing / covers a whole
// subtree; an exact entry wins over a subtree). A new package fails the
// test until it's placed here.
var tiers = map[string]int{
	"internal/axerr":                tierPure,
	"internal/jsonx":                tierPure,
	"internal/schema":               tierPure,
	"internal/schema/yamlsrc":       tierPure,
	"internal/config":               tierPure,
	"internal/migrate/":             tierPure,
	"internal/share":                tierPure,
	"internal/compositor/kdl":       tierPure,
	"internal/compositor/actions":   tierPure,
	"internal/compositor/render":    tierPure,
	"internal/calendar/ical":        tierPure,
	"internal/theme/palette":        tierPure,
	"internal/theme/integrations":   tierPure,
	"internal/hookup":               tierPure,
	"internal/greeterinstall/rules": tierPure,
	"internal/release":              tierPure,
	"internal/assets":               tierEdge,
	"internal/brightness":           tierEdge,
	"internal/buginfo":              tierEdge,
	"internal/buildinfo":            tierEdge,
	"internal/calendar":             tierEdge,
	"internal/chat":                 tierEdge,
	"internal/claudeusage":          tierEdge,
	"internal/clipboard":            tierEdge,
	"internal/command":              tierEdge,
	"internal/community":            tierEdge,
	"internal/compositor/binds":     tierEdge,
	"internal/compositor/edit":      tierEdge,
	"internal/compositor/ipc":       tierEdge,
	"internal/compositor/luacheck":  tierEdge,
	"internal/compositor/manager":   tierEdge,
	"internal/compositor/takeover":  tierEdge,
	"internal/compositor/userconf":  tierEdge,
	"internal/cursortheme":          tierEdge,
	"internal/dbus":                 tierEdge,
	"internal/deps":                 tierEdge,
	"internal/fsx":                  tierEdge,
	"internal/greeter":              tierEdge,
	"internal/greeterinstall":       tierEdge,
	"internal/release/fetch":        tierEdge,
	"internal/idle":                 tierEdge,
	"internal/filepicker":           tierEdge,
	"internal/files":                tierEdge,
	"internal/ipcroute":             tierEdge,
	"internal/lockscreen":           tierEdge,
	"internal/logfile":              tierEdge,
	"internal/logind":               tierEdge,
	"internal/media":                tierEdge,
	"internal/netif":                tierEdge,
	"internal/nightlight":           tierEdge,
	"internal/rpc":                  tierEdge,
	"internal/saved":                tierEdge,
	"internal/screensaver":          tierEdge,
	"internal/secrets":              tierEdge,
	"internal/selfupdate":           tierEdge,
	"internal/shellcmd":             tierEdge,
	"internal/nmvpn":                tierEdge,
	"internal/store":                tierEdge,
	"internal/supervise":            tierEdge,
	"internal/sysmon":               tierEdge,
	"internal/tailscale":            tierEdge,
	"internal/theme":                tierEdge,
	"internal/topics":               tierEdge,
	"internal/tree":                 tierEdge,
	"internal/tz":                   tierEdge,
	"internal/unixmsg":              tierEdge,
	"internal/updates":              tierEdge,
	"internal/wayland/":             tierEdge,
	"internal/weather":              tierEdge,
	"internal/xdg":                  tierEdge,
	"internal/daemon":               tierDaemon,
	"internal/cli":                  tierCLI,
	"cmd/":                          tierMain,
	"tools/":                        tierMain,
}

// Test helpers: an edge tier of their own that only _test.go files import
var testOnly = map[string]bool{
	"internal/archtest":              true,
	"internal/testkit":               true,
	"internal/dbus/dbustest":         true,
	"internal/logind/logindtest":     true,
	"internal/wayland/wire/wiretest": true,
}

// What a pure package may never import
var forbidden = []string{"os", "os/exec", "os/signal", "net", "syscall", "golang.org/x/sys", "io/ioutil", "plugin", "unsafe"}

// Package-level variables allowed to hold state, by package directory and
// name, each with why. Read-only tables (regexps, maps and slices never
// written after init), sentinel errors, go:embed variables and values
// computed once (sync.OnceValue) need no entry.
var allowedState = map[string]string{
	"internal/buildinfo.version": "set at link time (-ldflags -X), which only reaches a package variable",
	"internal/testkit.indexOnce": "a test helper: the shared fixtures' index, read once per test binary",
	"internal/testkit.index":     "a test helper: the shared fixtures' index, read once per test binary",
	"internal/testkit.indexErr":  "a test helper: the shared fixtures' index, read once per test binary",
	"internal/testkit.repoMu":    "a test helper: repo files parsed once per test binary",
	"internal/testkit.repoFiles": "a test helper: repo files parsed once per test binary",
}

// Types whose package-level variable is state, whatever its initializer
var stateTypes = map[string]bool{
	"sync.Map": true, "sync.Mutex": true, "sync.RWMutex": true, "sync.Once": true, "sync.WaitGroup": true, "sync.Pool": true,
	"atomic.Bool": true, "atomic.Int32": true, "atomic.Int64": true, "atomic.Uint32": true, "atomic.Uint64": true, "atomic.Uintptr": true, "atomic.Value": true, "atomic.Pointer": true,
}

// tierOf is the tier of a package directory under backend/, or false
func tierOf(rel string) (int, bool) {
	if t, ok := tiers[rel]; ok {
		return t, true
	}
	best, tier := "", 0
	for p, t := range tiers {
		if strings.HasSuffix(p, "/") && strings.HasPrefix(rel+"/", p) && len(p) > len(best) {
			best, tier = p, t
		}
	}
	return tier, best != ""
}

type pkg struct {
	rel   string
	name  string
	files map[string]*ast.File // by path, _test.go files included
}

// load parses every package under backend/
func load(t *testing.T) []*pkg {
	t.Helper()
	root, err := filepath.Abs("../..")
	if err != nil {
		t.Fatal(err)
	}
	byDir := map[string]*pkg{}
	err = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".go") {
			return err
		}
		rel, _ := filepath.Rel(root, filepath.Dir(path))
		rel = filepath.ToSlash(rel)
		f, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.ParseComments)
		if err != nil {
			return err
		}
		p := byDir[rel]
		if p == nil {
			p = &pkg{rel: rel, files: map[string]*ast.File{}}
			byDir[rel] = p
		}
		if !strings.HasSuffix(f.Name.Name, "_test") {
			p.name = f.Name.Name
		}
		p.files[path] = f
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	var pkgs []*pkg
	for _, p := range byDir {
		pkgs = append(pkgs, p)
	}
	sort.Slice(pkgs, func(i, j int) bool { return pkgs[i].rel < pkgs[j].rel })
	if len(pkgs) < 10 {
		t.Fatalf("found only %d packages", len(pkgs))
	}
	return pkgs
}

func isTest(path string) bool { return strings.HasSuffix(path, "_test.go") }

func TestEveryPackageIsClassified(t *testing.T) {
	t.Parallel()
	for _, p := range load(t) {
		_, ok := tierOf(p.rel)
		if !ok && !testOnly[p.rel] {
			t.Errorf("%s isn't classified: add it to archtest's tiers (or testOnly)", p.rel)
		}
	}
}

func TestImportsPointDown(t *testing.T) {
	t.Parallel()
	for _, p := range load(t) {
		tier, ok := tierOf(p.rel)
		if testOnly[p.rel] {
			tier, ok = tierEdge, true
		}
		if !ok {
			continue // TestEveryPackageIsClassified reports it
		}
		for path, f := range p.files {
			for _, imp := range f.Imports {
				name, _ := strconv.Unquote(imp.Path.Value)
				if tier == tierPure && !isTest(path) {
					for _, bad := range forbidden {
						if name == bad || strings.HasPrefix(name, bad+"/") {
							t.Errorf("%s (pure) imports %s", p.rel, name)
						}
					}
				}
				own, ok := strings.CutPrefix(name, module)
				if !ok {
					continue
				}
				if testOnly[own] {
					if !isTest(path) && !testOnly[p.rel] {
						t.Errorf("%s imports the test helper %s outside a _test.go file", filepath.Base(path), own)
					}
					continue
				}
				if isTest(path) {
					continue // a test may reach up to build what it tests
				}
				if dep, ok := tierOf(own); ok && dep > tier {
					t.Errorf("%s (%s) imports %s (%s): imports only point down", p.rel, tierNames[tier], own, tierNames[dep])
				}
			}
		}
	}
}

func TestEveryPackageHasADocComment(t *testing.T) {
	t.Parallel()
	for _, p := range load(t) {
		// The package's doc comment: in one file, a _test.go one only when
		// the package has nothing else
		var doc, testDoc string
		var docFiles []string
		onlyTests := true
		for path, f := range p.files {
			onlyTests = onlyTests && isTest(path)
			switch {
			case f.Doc == nil:
			case isTest(path):
				testDoc = f.Doc.Text()
			default:
				doc = f.Doc.Text()
				docFiles = append(docFiles, filepath.Base(path))
			}
		}
		if len(docFiles) > 1 {
			sort.Strings(docFiles)
			t.Errorf("%s has a doc comment in %d files (%s): keep one", p.rel, len(docFiles), strings.Join(docFiles, ", "))
			continue
		}
		if onlyTests {
			doc = testDoc
		}
		want := "Package " + p.name + " "
		if p.name == "main" {
			want = "Command " + filepath.Base(p.rel) + " "
		}
		if !strings.HasPrefix(doc, want) {
			t.Errorf("%s has no doc comment (\"%s…\")", p.rel, want)
			continue
		}
		tier, ok := tierOf(p.rel)
		if pure, marked := ok && tier == tierPure && !testOnly[p.rel], strings.Contains(doc, "Pure:"); pure != marked {
			t.Errorf("%s: its doc comment says \"Pure:\" = %v, archtest's tiers say pure = %v", p.rel, marked, pure)
		}
	}
}

func TestNoInitOrPackageState(t *testing.T) {
	t.Parallel()
	for _, p := range load(t) {
		// The package-level variables, by name and by declaration
		names := map[string]bool{}
		specs := map[*ast.ValueSpec]bool{}
		for path, f := range p.files {
			if isTest(path) {
				continue
			}
			for _, decl := range f.Decls {
				switch d := decl.(type) {
				case *ast.FuncDecl:
					if d.Name.Name == "init" && d.Recv == nil {
						t.Errorf("%s: %s declares init()", p.rel, filepath.Base(path))
					}
				case *ast.GenDecl:
					if d.Tok != token.VAR {
						continue
					}
					for _, s := range d.Specs {
						vs := s.(*ast.ValueSpec)
						specs[vs] = true
						for _, n := range vs.Names {
							names[n.Name] = true
							if _, ok := allowedState[p.rel+"."+n.Name]; ok {
								continue
							}
							if why := stateful(d, vs); why != "" {
								t.Errorf("%s.%s is package state (%s): move it into a struct, or allow it in archtest with why", p.rel, n.Name, why)
							}
						}
					}
				}
			}
		}
		// Nothing writes one after init
		for path, f := range p.files {
			if isTest(path) {
				continue
			}
			ast.Inspect(f, func(n ast.Node) bool {
				var targets []ast.Expr
				switch s := n.(type) {
				case *ast.AssignStmt:
					if s.Tok != token.DEFINE {
						targets = s.Lhs
					}
				case *ast.IncDecStmt:
					targets = []ast.Expr{s.X}
				case *ast.CallExpr:
					if fn, ok := s.Fun.(*ast.Ident); ok && fn.Obj == nil && (fn.Name == "delete" || fn.Name == "clear") && len(s.Args) > 0 {
						targets = s.Args[:1]
					}
				case *ast.FuncDecl:
					return s.Body != nil
				}
				for _, e := range targets {
					id := root(e)
					if id == nil || id.Name == "_" {
						continue
					}
					global := id.Obj == nil && names[id.Name] // declared in another file
					if id.Obj != nil {
						vs, _ := id.Obj.Decl.(*ast.ValueSpec)
						global = specs[vs]
					}
					if _, ok := allowedState[p.rel+"."+id.Name]; global && !ok {
						t.Errorf("%s: %s writes the package variable %s", p.rel, filepath.Base(path), id.Name)
					}
				}
				return true
			})
		}
	}
}

// stateful says why a package-level variable holds state, or ""
func stateful(d *ast.GenDecl, vs *ast.ValueSpec) string {
	if t := typeName(vs.Type); t != "" {
		return t
	}
	if len(vs.Values) == 0 {
		for _, c := range append(commentList(d.Doc), commentList(vs.Doc)...) {
			if strings.HasPrefix(c, "//go:embed ") {
				return ""
			}
		}
		return "no initializer"
	}
	for _, v := range vs.Values {
		// T{}, &T{} and new(T)
		if u, ok := v.(*ast.UnaryExpr); ok && u.Op == token.AND {
			v = u.X
		}
		switch x := v.(type) {
		case *ast.CompositeLit:
			if t := typeName(x.Type); t != "" {
				return t
			}
		case *ast.CallExpr:
			if fn, ok := x.Fun.(*ast.Ident); ok && fn.Name == "new" && len(x.Args) == 1 {
				if t := typeName(x.Args[0]); t != "" {
					return t
				}
			}
		}
	}
	return ""
}

// typeName is a state type's name if e is one (or a pointer to or an
// instance of a generic one), else ""
func typeName(e ast.Expr) string {
	if star, ok := e.(*ast.StarExpr); ok {
		e = star.X
	}
	if idx, ok := e.(*ast.IndexExpr); ok {
		e = idx.X
	}
	if n := exprString(e); stateTypes[n] {
		return n
	}
	return ""
}

func commentList(g *ast.CommentGroup) []string {
	var out []string
	if g != nil {
		for _, c := range g.List {
			out = append(out, c.Text)
		}
	}
	return out
}

// root is the variable an assignment target writes into (m in m[k], s.f,
// *p, (x))
func root(e ast.Expr) *ast.Ident {
	for {
		switch x := e.(type) {
		case *ast.Ident:
			return x
		case *ast.IndexExpr:
			e = x.X
		case *ast.SelectorExpr:
			e = x.X
		case *ast.StarExpr:
			e = x.X
		case *ast.ParenExpr:
			e = x.X
		default:
			return nil
		}
	}
}

func exprString(e ast.Expr) string {
	switch x := e.(type) {
	case *ast.Ident:
		return x.Name
	case *ast.SelectorExpr:
		return exprString(x.X) + "." + x.Sel.Name
	case *ast.StarExpr:
		return "*" + exprString(x.X)
	}
	return ""
}
