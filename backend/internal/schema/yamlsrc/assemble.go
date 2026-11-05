package yamlsrc

import (
	"fmt"
	"io/fs"
	"path"
	"sort"
	"strings"
	"unicode"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// The source layout, relative to the tree's root
const (
	SourceDir       = "config/schema"
	IndexFile       = SourceDir + "/index.yaml"
	AnnotationsFile = SourceDir + "/annotations.yaml"
	SectionsDir     = SourceDir + "/sections"
	DefinitionsDir  = SourceDir + "/definitions"
	// TypeFile is a type's definition in its folder <root>/<Type>/
	TypeFile = "schema.yaml"
)

// Assemble reads the schema source in fsys (the axiom tree) and joins it
// into the root schema: index.yaml as the root, its `properties` followed
// by sections/<Name>.yaml for each name `sections` lists (every file
// listed, every name with a file), then `definitions`: each
// definitions/**/<Name>.yaml, and each type folder's schema.yaml under the
// roots index.yaml's `kinds` name, as <Type><suffix>. The result must pass
// Check.
func Assemble(fsys fs.FS) (*jsonx.Object, error) {
	a := &assembler{fsys: fsys, pos: Positions{}}
	root := a.assemble()
	registry := a.annotations()
	// Report everything at once: the listing problems and what the files
	// that did read hold
	if root != nil && registry != nil {
		a.errs = append(a.errs, Check(root, registry, a.pos)...)
	}
	if len(a.errs) > 0 {
		return nil, a.errs
	}
	return root, nil
}

// Kind is a kind of type kept in folders: bar widgets, overlay modules,
// overlay views (index.yaml's `kinds`).
type Kind struct {
	Name string // the definition whose oneOf lists the types (BarWidget)
	// Root holds the type folders (components/bar/widgets); Suffix ends
	// each type's definition name (Weather → WeatherWidget); Base names
	// the definition each type's schema.yaml is expanded into (kinds.go)
	Root, Suffix, Base string
}

type assembler struct {
	fsys fs.FS
	pos  Positions
	errs Errors
}

func (a *assembler) read(name string) any {
	data, err := fs.ReadFile(a.fsys, name)
	if err != nil {
		a.errs = append(a.errs, &Error{File: name, Msg: err.Error()})
		return nil
	}
	v, _, err := ParsePositions(name, data, a.pos)
	if err != nil {
		if es, ok := err.(Errors); ok {
			a.errs = append(a.errs, es...)
		} else {
			a.errs = append(a.errs, err.(*Error))
		}
		return nil
	}
	return v
}

func (a *assembler) names(index *jsonx.Object, key string) []string {
	list, ok := index.Value(key).(*jsonx.Array)
	if !ok {
		a.errs = append(a.errs, a.pos.At(index, key, IndexFile, key+" must be a list of names"))
		return nil
	}
	var names []string
	seen := map[string]bool{}
	for _, v := range list.Items {
		name, ok := v.(string)
		if !ok || name == "" || strings.ContainsAny(name, "/\\") {
			a.errs = append(a.errs, a.pos.At(index, key, IndexFile, fmt.Sprintf("%s: %v isn't a name", key, v)))
			continue
		}
		if seen[name] {
			a.errs = append(a.errs, a.pos.At(index, key, IndexFile, fmt.Sprintf("%s lists %s twice", key, name)))
			continue
		}
		seen[name] = true
		names = append(names, name)
	}
	return names
}

// kinds reads index.yaml's `kinds`: { <Name>: { root, suffix, base? } }.
func (a *assembler) kinds(index *jsonx.Object) []Kind {
	if !index.Has("kinds") {
		return nil
	}
	obj, ok := index.Value("kinds").(*jsonx.Object)
	if !ok {
		a.errs = append(a.errs, a.pos.At(index, "kinds", IndexFile, "kinds must be a mapping of { root, suffix }"))
		return nil
	}
	var out []Kind
	for _, name := range obj.Keys() {
		spec, _ := obj.Value(name).(*jsonx.Object)
		var root, suffix, base string
		valid := spec != nil
		if valid {
			root, _ = spec.Value("root").(string)
			suffix, _ = spec.Value("suffix").(string)
			base, _ = spec.Value("base").(string)
			for _, k := range spec.Keys() {
				valid = valid && (k == "root" || k == "suffix" || k == "base")
			}
		}
		if !valid || root == "" || suffix == "" || (spec.Has("base") && base == "") || !fs.ValidPath(root) {
			a.errs = append(a.errs, a.pos.At(obj, name, IndexFile, "a kind is { root: <folder in the tree>, suffix: <definition name ending>, base: <definition> }"))
			continue
		}
		out = append(out, Kind{Name: name, Root: root, Suffix: suffix, Base: base})
	}
	return out
}

func (a *assembler) assemble() *jsonx.Object {
	index, ok := a.read(IndexFile).(*jsonx.Object)
	if !ok {
		if len(a.errs) == 0 {
			a.errs = append(a.errs, &Error{File: IndexFile, Msg: "must be a mapping"})
		}
		return nil
	}
	sections := a.names(index, "sections")
	sectionFiles := a.files(SectionsDir, false)
	a.listedExactly(index, "sections", sections, sectionFiles)
	if !index.Has("properties") {
		a.errs = append(a.errs, &Error{File: IndexFile, Msg: "needs properties (the sections follow them)"})
	}
	if index.Has("definitions") {
		a.errs = append(a.errs, a.pos.At(index, "definitions", IndexFile, "definitions are found, not listed: definitions/**/<Name>.yaml and the type folders"))
	}
	kinds := a.kinds(index)
	definitions := a.definitions(kinds)

	root := jsonx.NewObject()
	for _, key := range index.Keys() {
		switch key {
		case "sections", "kinds", "definitions":
			continue
		case "properties":
			props, ok := index.Value(key).(*jsonx.Object)
			if !ok {
				a.errs = append(a.errs, a.pos.At(index, key, IndexFile, "properties must be a mapping"))
				continue
			}
			for _, name := range sections {
				if props.Has(name) {
					a.errs = append(a.errs, a.pos.At(props, name, IndexFile, name+" is both in properties and a section file"))
					continue
				}
				if file, ok := sectionFiles[name]; ok {
					props.Set(name, a.read(file))
				}
			}
			root.Set(key, props)
		default:
			root.Set(key, index.Value(key))
		}
	}
	root.Set("definitions", definitions)
	props, _ := root.Value("properties").(*jsonx.Object)
	a.expandKinds(kinds, definitions, props)
	a.inlineExtensions(root)
	a.deriveInherits(root)
	a.fillAxiomActions(root)
	orderKeys(root)
	return root
}

// typeFolders lists a kind's type folders that have a schema.yaml, by
// name. Type folders are UpperCamel; lowercase ones (base/, parts/) hold
// what the types share, and a type without settings of its own
// (popout-only content) has no schema.yaml.
func typeFolders(fsys fs.FS, k Kind) ([]string, error) {
	entries, err := fs.ReadDir(fsys, k.Root)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, e := range entries {
		if !e.IsDir() || !unicode.IsUpper(rune(e.Name()[0])) {
			continue
		}
		if _, err := fs.Stat(fsys, path.Join(k.Root, e.Name(), TypeFile)); err == nil {
			out = append(out, e.Name())
		}
	}
	return out, nil
}

// definitions joins definitions/**/<Name>.yaml (in path order) and then
// each kind's type folders (in name order).
func (a *assembler) definitions(kinds []Kind) *jsonx.Object {
	defs := jsonx.NewObject()
	where := map[string]string{}
	add := func(name, file string) {
		if other, dup := where[name]; dup {
			a.errs = append(a.errs, &Error{File: file, Msg: "the definition " + name + " is also " + other})
			return
		}
		where[name] = file
		defs.Set(name, a.read(file))
	}
	common := a.files(DefinitionsDir, true)
	files := make([]string, 0, len(common))
	byFile := map[string]string{}
	for name, file := range common {
		files = append(files, file)
		byFile[file] = name
	}
	sort.Strings(files)
	for _, file := range files {
		add(byFile[file], file)
	}
	for _, k := range kinds {
		types, err := typeFolders(a.fsys, k)
		if err != nil {
			a.errs = append(a.errs, &Error{File: k.Root, Msg: err.Error()})
			continue
		}
		for _, t := range types {
			add(t+k.Suffix, path.Join(k.Root, t, TypeFile))
		}
	}
	return defs
}

// files maps each .yaml file's name (its stem) under dir to its path.
func (a *assembler) files(dir string, nested bool) map[string]string {
	found := map[string]string{}
	err := fs.WalkDir(a.fsys, dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if p != dir && !nested {
				a.errs = append(a.errs, &Error{File: p, Msg: "sections/ holds files only"})
				return fs.SkipDir
			}
			return nil
		}
		if !strings.HasSuffix(p, ".yaml") {
			a.errs = append(a.errs, &Error{File: p, Msg: "only .yaml files belong here"})
			return nil
		}
		name := strings.TrimSuffix(path.Base(p), ".yaml")
		if other, dup := found[name]; dup {
			a.errs = append(a.errs, &Error{File: p, Msg: "the name " + name + " is also " + other})
			return nil
		}
		found[name] = p
		return nil
	})
	if err != nil {
		a.errs = append(a.errs, &Error{File: dir, Msg: err.Error()})
	}
	return found
}

func (a *assembler) listedExactly(index *jsonx.Object, key string, listed []string, files map[string]string) {
	isListed := map[string]bool{}
	for _, name := range listed {
		isListed[name] = true
		if _, ok := files[name]; !ok {
			a.errs = append(a.errs, a.pos.At(index, key, IndexFile, fmt.Sprintf("%s lists %s, which has no file", key, name)))
		}
	}
	var unlisted []string
	for name, file := range files {
		if !isListed[name] {
			unlisted = append(unlisted, file)
		}
	}
	sort.Strings(unlisted)
	for _, file := range unlisted {
		a.errs = append(a.errs, &Error{File: file, Msg: fmt.Sprintf("not listed in %s's %s", IndexFile, key)})
	}
}

// annotations reads the registry: every x-* key the schema may use (nil
// when it can't be read).
func (a *assembler) annotations() map[string]bool {
	before := len(a.errs)
	reg, ok := a.read(AnnotationsFile).(*jsonx.Object)
	if len(a.errs) > before {
		return nil
	}
	if !ok {
		a.errs = append(a.errs, &Error{File: AnnotationsFile, Msg: "must be a mapping of annotation names"})
		return nil
	}
	names := map[string]bool{}
	for _, k := range reg.Keys() {
		if !strings.HasPrefix(k, "x-") {
			a.errs = append(a.errs, a.pos.At(reg, k, AnnotationsFile, k+" isn't an x-* name"))
			continue
		}
		names[k] = true
	}
	return names
}

// Roots are the folders whose YAML a watcher follows: the source and each
// kind's root (index.yaml decides where those are).
func Roots(fsys fs.FS) []string {
	a := &assembler{fsys: fsys, pos: Positions{}}
	out := []string{SourceDir}
	if index, ok := a.read(IndexFile).(*jsonx.Object); ok {
		for _, k := range a.kinds(index) {
			out = append(out, k.Root)
		}
	}
	return out
}
