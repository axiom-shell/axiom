// Package account is the user's own account, for Settings › General ›
// Account: their login and real name, picture and whether they're an
// administrator, read from AccountsService (org.freedesktop.Accounts) or,
// without it, /etc/passwd, /etc/group and ~/.face; and the changes a user
// makes to their own account: the picture (squared and scaled into
// ~/.face, then handed to AccountsService, which the greeter reads), the
// real name, and the password (passwd, driven through a pty: password.go).
// Docs: docs/dev/features/account.md.
package account

import (
	"bytes"
	"context"
	"errors"
	"image"
	_ "image/gif" // decoders, registered for image.Decode
	_ "image/jpeg"
	"image/png"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"

	_ "golang.org/x/image/bmp"
	"golang.org/x/image/draw"
	_ "golang.org/x/image/webp"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// AccountsService's names
const (
	accountsBus   = "org.freedesktop.Accounts"
	accountsPath  = dbus.ObjectPath("/org/freedesktop/Accounts")
	accountsIface = "org.freedesktop.Accounts"
	userIface     = "org.freedesktop.Accounts.User"
)

// The picture: at most this big to read, saved this many pixels square
const (
	maxPicture  = 32 << 20
	pictureSize = 256
)

// How long a change waits, polkit's prompt included
const setTimeout = 2 * time.Minute

// Account is the user as Settings shows them.
type Account struct {
	Login    string `json:"login"`
	RealName string `json:"realName"`
	// The picture's path ("" for none): AccountsService's, else ~/.face
	Icon  string `json:"icon"`
	Admin bool   `json:"admin"`
	// AccountsService answered (the picture reaches the greeter, the
	// real name can be changed)
	Accounts bool `json:"accounts"`
}

// Options say whose account and where it's read from.
type Options struct {
	UID   int
	Login string
	Home  string
	// SystemBus dials the system bus; nil: no AccountsService
	SystemBus func(ctx context.Context) (*dbus.Conn, error)
	// Root prefixes /etc/passwd and /etc/group (tests: a temp dir)
	Root string
	// Passwd is the command changing the password (default passwd)
	Passwd []string
	// PasswordTimeout bounds a password change (default 30 s)
	PasswordTimeout time.Duration
	Log             *slog.Logger
}

// Accounts reads and changes the account.
type Accounts struct{ o Options }

// New is an Accounts.
func New(o Options) *Accounts {
	if len(o.Passwd) == 0 {
		o.Passwd = []string{"passwd"}
	}
	if o.PasswordTimeout == 0 {
		o.PasswordTimeout = 30 * time.Second
	}
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	return &Accounts{o: o}
}

func (a *Accounts) face() string { return filepath.Join(a.o.Home, ".face") }

// Get reads the account: AccountsService's view when it answers, else
// the files'.
func (a *Accounts) Get(ctx context.Context) Account {
	acc := a.fromFiles()
	conn, user, err := a.user(ctx)
	if err != nil {
		return acc
	}
	defer conn.Close()
	props, err := conn.GetAll(ctx, accountsBus, user, userIface)
	if err != nil {
		return acc
	}
	acc.Accounts = true
	if name, _ := props["RealName"].Value.(string); name != "" {
		acc.RealName = name
	}
	if kind, ok := props["AccountType"].Value.(int32); ok {
		acc.Admin = kind == 1
	}
	if icon, _ := props["IconFile"].Value.(string); icon != "" && fsx.IsFile(icon) {
		acc.Icon = icon
	}
	return acc
}

// fromFiles is the account from /etc/passwd's GECOS, /etc/group's wheel,
// sudo and admin groups, and ~/.face.
func (a *Accounts) fromFiles() Account {
	acc := Account{Login: a.o.Login}
	if data, err := os.ReadFile(filepath.Join(a.o.Root, "/etc/passwd")); err == nil {
		acc.RealName = realNameOf(string(data), a.o.Login)
	}
	if data, err := os.ReadFile(filepath.Join(a.o.Root, "/etc/group")); err == nil {
		acc.Admin = inAdminGroup(string(data), a.o.Login)
	}
	if fsx.IsFile(a.face()) {
		acc.Icon = a.face()
	}
	return acc
}

// user is AccountsService's object for the user, on a connection the
// caller closes.
func (a *Accounts) user(ctx context.Context) (*dbus.Conn, dbus.ObjectPath, error) {
	if a.o.SystemBus == nil {
		return nil, "", axerr.New(axerr.Unavailable, "no system bus")
	}
	conn, err := a.o.SystemBus(ctx)
	if err != nil {
		return nil, "", err
	}
	m, err := conn.Call(ctx, accountsBus, accountsPath, accountsIface, "FindUserById", "x", int64(a.o.UID))
	if err != nil {
		conn.Close()
		return nil, "", err
	}
	var path dbus.ObjectPath
	if err := m.Store(&path); err != nil {
		conn.Close()
		return nil, "", axerr.Wrap(axerr.Internal, err, "FindUserById")
	}
	return conn, path, nil
}

// SetIcon makes the image at path the user's picture: its middle square,
// scaled to 256 px, written to ~/.face as a PNG, then handed to
// AccountsService when it's there (it keeps its own copy, which the login
// screen shows). An empty path removes the picture.
func (a *Accounts) SetIcon(ctx context.Context, path string) (Account, error) {
	if path == "" {
		if err := os.Remove(a.face()); err != nil && !errors.Is(err, os.ErrNotExist) {
			return Account{}, axerr.Wrap(axerr.Unavailable, err, "removing ~/.face")
		}
		// AccountsService takes "" as no picture
		if err := a.setOnUser(ctx, "SetIconFile", ""); err != nil && axerr.KindOf(err) != axerr.Unavailable {
			return Account{}, err
		}
		return a.Get(ctx), nil
	}
	data, err := picture(path)
	if err != nil {
		return Account{}, err
	}
	if err := fsx.WriteFile(a.face(), data, 0o644); err != nil {
		return Account{}, err
	}
	if err := a.setOnUser(ctx, "SetIconFile", a.face()); err != nil && axerr.KindOf(err) != axerr.Unavailable {
		return Account{}, err
	}
	return a.Get(ctx), nil
}

// SetRealName changes the real name (AccountsService only: changing
// /etc/passwd needs chfn, which only an administrator's terminal runs).
func (a *Accounts) SetRealName(ctx context.Context, name string) (Account, error) {
	name = strings.TrimSpace(name)
	if !utf8.ValidString(name) || len(name) > 256 || strings.ContainsAny(name, ":,\n\x00") {
		return Account{}, axerr.New(axerr.BadRequest, "a real name can't hold : , or a new line")
	}
	if err := a.setOnUser(ctx, "SetRealName", name); err != nil {
		return Account{}, err
	}
	return a.Get(ctx), nil
}

func (a *Accounts) setOnUser(ctx context.Context, member string, value string) error {
	ctx, cancel := context.WithTimeout(ctx, setTimeout)
	defer cancel()
	conn, user, err := a.user(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = conn.CallInteractive(ctx, accountsBus, user, userIface, member, "s", value)
	return err
}

// picture reads an image file and gives its middle square at
// pictureSize, as a PNG.
func picture(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, axerr.Wrap(axerr.NotFound, err, "the picture")
	}
	defer f.Close()
	if st, err := f.Stat(); err != nil || !st.Mode().IsRegular() || st.Size() > maxPicture {
		return nil, axerr.New(axerr.BadRequest, "the picture must be an image file of at most 32 MB")
	}
	src, _, err := image.Decode(f)
	if err != nil {
		return nil, axerr.Wrap(axerr.BadRequest, err, "not an image axiom can read (PNG, JPEG, WebP, GIF or BMP)")
	}
	b := src.Bounds()
	side := min(b.Dx(), b.Dy())
	if side == 0 {
		return nil, axerr.New(axerr.BadRequest, "the picture is empty")
	}
	corner := image.Pt(b.Min.X+(b.Dx()-side)/2, b.Min.Y+(b.Dy()-side)/2)
	square := image.Rectangle{Min: corner, Max: corner.Add(image.Pt(side, side))}
	out := image.NewRGBA(image.Rect(0, 0, min(side, pictureSize), min(side, pictureSize)))
	draw.CatmullRom.Scale(out, out.Bounds(), src, square, draw.Src, nil)
	var buf bytes.Buffer
	if err := png.Encode(&buf, out); err != nil {
		return nil, axerr.Wrap(axerr.Internal, err, "encoding the picture")
	}
	return buf.Bytes(), nil
}

// realNameOf is the GECOS full name (its first comma-separated field) of
// login in a passwd file.
func realNameOf(passwd, login string) string {
	for line := range strings.Lines(passwd) {
		f := strings.Split(strings.TrimRight(line, "\n"), ":")
		if len(f) >= 5 && f[0] == login {
			name, _, _ := strings.Cut(f[4], ",")
			return strings.TrimSpace(name)
		}
	}
	return ""
}

// inAdminGroup: login is a member of wheel, sudo or admin in a group file
// (the groups distributions give sudo to).
func inAdminGroup(group, login string) bool {
	for line := range strings.Lines(group) {
		f := strings.Split(strings.TrimRight(line, "\n"), ":")
		if len(f) < 4 || (f[0] != "wheel" && f[0] != "sudo" && f[0] != "admin") {
			continue
		}
		for _, member := range strings.Split(f[3], ",") {
			if strings.TrimSpace(member) == login {
				return true
			}
		}
	}
	return false
}
