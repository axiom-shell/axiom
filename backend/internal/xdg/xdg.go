// Package xdg is where axiom keeps things: the XDG base directories (as
// components/methods/DataDirs.qml resolves them, so the shell and the
// binary agree) and the per-display runtime directory holding the daemon's
// socket and locks, which must be private (see Runtime).
package xdg

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Dirs are axiom's folders, each ending in "/" (DataDirs.xdg).
type Dirs struct {
	Config          string `json:"config"`          // config.json, saved/
	State           string `json:"state"`           // secrets, chats, generated configs
	UI              string `json:"ui"`              // StateManager's files
	Data            string `json:"data"`            //
	Notes           string `json:"notes"`           // the default notes folder
	GeneratedThemes string `json:"generatedThemes"` // themes made from wallpapers
	CommunityThemes string `json:"communityThemes"` // palettes community setups brought
	Cache           string `json:"cache"`           // what can be downloaded again
}

// Resolve is DataDirs.xdg: each $XDG_*_HOME when absolute, else its
// default under $HOME.
func Resolve(getenv func(string) string) Dirs {
	config := base(getenv, "XDG_CONFIG_HOME", ".config") + "/axiom/"
	state := base(getenv, "XDG_STATE_HOME", ".local/state") + "/axiom/"
	data := base(getenv, "XDG_DATA_HOME", ".local/share") + "/axiom/"
	return Dirs{
		Config:          config,
		State:           state,
		UI:              state + "ui/",
		Data:            data,
		Notes:           data + "notes/",
		GeneratedThemes: state + "themes/",
		CommunityThemes: data + "themes/",
		Cache:           base(getenv, "XDG_CACHE_HOME", ".cache") + "/axiom/",
	}
}

// Bases are the XDG base directories themselves (no trailing "/"), where
// other apps keep their files (the theme integrations write there).
type Bases struct{ Home, Config, State, Data string }

// ResolveBases is Resolve's folders without axiom's own.
func ResolveBases(getenv func(string) string) Bases {
	return Bases{
		Home:   strings.TrimRight(getenv("HOME"), "/"),
		Config: base(getenv, "XDG_CONFIG_HOME", ".config"),
		State:  base(getenv, "XDG_STATE_HOME", ".local/state"),
		Data:   base(getenv, "XDG_DATA_HOME", ".local/share"),
	}
}

var trailingSlashes = regexp.MustCompile(`(.)/+$`)

func base(getenv func(string) string, name, fallback string) string {
	value := strings.TrimSpace(getenv(name))
	if strings.HasPrefix(value, "/") {
		return trailingSlashes.ReplaceAllString(value, "$1")
	}
	return strings.TrimRight(getenv("HOME"), "/") + "/" + fallback
}

// SearchDirs is DataDirs.searchDirs: $XDG_DATA_HOME, then $XDG_DATA_DIRS'
// absolute entries (or /usr/local/share and /usr/share), each once.
func SearchDirs(getenv func(string) string) []string {
	var system []string
	for _, d := range strings.Split(getenv("XDG_DATA_DIRS"), ":") {
		d = strings.TrimSpace(d)
		if strings.HasPrefix(d, "/") {
			system = append(system, trailingSlashes.ReplaceAllString(d, "$1"))
		}
	}
	if len(system) == 0 {
		system = []string{"/usr/local/share", "/usr/share"}
	}
	dirs := append([]string{base(getenv, "XDG_DATA_HOME", ".local/share")}, system...)
	var out []string
	seen := map[string]bool{}
	for _, d := range dirs {
		if !seen[d] {
			seen[d] = true
			out = append(out, d)
		}
	}
	return out
}

// Runtime is a display's private runtime directory,
// $XDG_RUNTIME_DIR/axiom/<display>/, holding the daemon's socket and lock.
type Runtime struct {
	Dir     string // $XDG_RUNTIME_DIR/axiom/<display>
	Display string // the display's name, as the directory names it
}

// Socket is the daemon's socket.
func (r Runtime) Socket() string { return filepath.Join(r.Dir, "axiom.sock") }

// Lock is the instance lock: held by the one daemon of the display.
func (r Runtime) Lock() string { return filepath.Join(r.Dir, "daemon.lock") }

// File is a file of the runtime directory (the schema and config the
// daemon hands the shell).
func (r Runtime) File(name string) string { return filepath.Join(r.Dir, name) }

// MaxSocketPath is the longest path a unix socket can be bound at.
const MaxSocketPath = 107

var displayName = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

// DisplayName is the runtime directory's name for a display: the
// $WAYLAND_DISPLAY socket's name (it may be a path), or "" when there is
// none or it holds characters a directory name shouldn't.
func DisplayName(waylandDisplay string) string {
	name := filepath.Base(strings.TrimSpace(waylandDisplay))
	if name == "." || name == "/" || !displayName.MatchString(name) || name == ".." {
		return ""
	}
	return name
}

// RuntimeRoot is $XDG_RUNTIME_DIR/axiom, checked private. Never a /tmp
// fallback: without $XDG_RUNTIME_DIR there's no directory only this user
// can reach.
func RuntimeRoot(getenv func(string) string, create bool) (string, error) {
	rt := getenv("XDG_RUNTIME_DIR")
	if !filepath.IsAbs(rt) {
		return "", axerr.New(axerr.Unavailable, "$XDG_RUNTIME_DIR isn't set (axiom keeps its socket there, nowhere else)")
	}
	if err := checkOwned(rt, false); err != nil {
		return "", err
	}
	root := filepath.Join(rt, "axiom")
	if err := PrivateDir(root, create); err != nil {
		return "", err
	}
	return root, nil
}

// ForDisplay is the runtime directory of the display named by
// $WAYLAND_DISPLAY (made private when create).
func ForDisplay(getenv func(string) string, create bool) (Runtime, error) {
	display := DisplayName(getenv("WAYLAND_DISPLAY"))
	if display == "" {
		return Runtime{}, axerr.New(axerr.Unavailable, "no usable $WAYLAND_DISPLAY to run on")
	}
	root, err := RuntimeRoot(getenv, create)
	if err != nil {
		return Runtime{}, err
	}
	dir := filepath.Join(root, display)
	r := Runtime{Dir: dir, Display: display}
	// A unix socket's path fits in sun_path (108 bytes with its NUL)
	if n := len(r.Socket()); n > MaxSocketPath {
		return Runtime{}, axerr.New(axerr.Unavailable, "the socket path %s is %d bytes, more than a unix socket allows (%d): use a shorter $XDG_RUNTIME_DIR", r.Socket(), n, MaxSocketPath)
	}
	if err := PrivateDir(dir, create); err != nil {
		return Runtime{}, err
	}
	return r, nil
}

// PrivateDir makes sure dir is a directory only this user can reach: made
// 0700 when missing (and create), else it must be a real directory (not a
// symlink) owned by this user, whose mode is narrowed to 0700 if wider.
func PrivateDir(dir string, create bool) error {
	if create {
		if err := os.Mkdir(dir, 0o700); err != nil && !errors.Is(err, fs.ErrExist) {
			return axerr.Wrap(axerr.Unavailable, err, "making %s", dir)
		}
	}
	return checkOwned(dir, true)
}

func checkOwned(dir string, narrow bool) error {
	info, err := os.Lstat(dir)
	if err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "%s", dir)
	}
	if info.Mode()&fs.ModeSymlink != 0 || !info.IsDir() {
		return axerr.New(axerr.Refused, "%s isn't a directory (a symlink or file there is refused)", dir)
	}
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok || int(st.Uid) != os.Geteuid() {
		return axerr.New(axerr.Refused, "%s isn't owned by this user", dir)
	}
	if narrow && info.Mode().Perm() != 0o700 {
		if err := os.Chmod(dir, 0o700); err != nil {
			return axerr.Wrap(axerr.Refused, err, "%s is mode %o and can't be made 0700", dir, info.Mode().Perm())
		}
	}
	return nil
}

// Describe is dirs as text, for `axiom config path` and logs.
func (d Dirs) Describe() string {
	return fmt.Sprintf("config %s\nstate %s\ndata %s\ncache %s", d.Config, d.State, d.Data, d.Cache)
}
