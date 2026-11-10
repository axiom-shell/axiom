package account

import (
	"context"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

func write(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o755); err != nil {
		t.Fatal(err)
	}
}

func ctx(t *testing.T) context.Context {
	t.Helper()
	c, cancel := context.WithTimeout(context.Background(), testkit.Bound(10*time.Second))
	t.Cleanup(cancel)
	return c
}

func TestFromFiles(t *testing.T) {
	t.Parallel()
	root, home := t.TempDir(), t.TempDir()
	write(t, filepath.Join(root, "etc/passwd"), "root:x:0:0::/root:/bin/bash\nme:x:1000:1000:Alex Doe,,,:/home/me:/bin/zsh\n")
	write(t, filepath.Join(root, "etc/group"), "root:x:0:\nwheel:x:998:me,other\naudio:x:995:me\n")
	write(t, filepath.Join(home, ".face"), "png")
	a := New(Options{UID: 1000, Login: "me", Home: home, Root: root})
	got := a.Get(ctx(t))
	want := Account{Login: "me", RealName: "Alex Doe", Icon: filepath.Join(home, ".face"), Admin: true}
	if got != want {
		t.Errorf("Get = %+v, want %+v", got, want)
	}
	if inAdminGroup("wheel:x:998:other\n", "me") {
		t.Error("another user's wheel made me an administrator")
	}
}

// fakeAccounts is AccountsService with one user, its setters recorded and
// refused without interactive authorization, as polkit would
type fakeAccounts struct {
	mu    sync.Mutex
	props map[string]any
	calls []string
}

func newFakeAccounts(t *testing.T, bus *dbustest.Bus) *fakeAccounts {
	t.Helper()
	conn, err := dbus.Dial(ctx(t), bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	f := &fakeAccounts{props: map[string]any{"RealName": "Travis", "AccountType": int32(1), "IconFile": ""}}
	user := dbus.ObjectPath("/org/freedesktop/Accounts/User1000")
	if _, err := conn.Export(accountsPath, dbus.Interface{Name: accountsIface, Methods: map[string]dbus.Method{
		"FindUserById": {In: "x", Out: "o", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			if m.Body[0] != int64(1000) {
				return nil, dbus.NewError("org.freedesktop.Accounts.Error.Failed", "no such user")
			}
			return []any{user}, nil
		}},
	}}); err != nil {
		t.Fatal(err)
	}
	setter := func(prop string) dbus.Method {
		return dbus.Method{In: "s", Fn: func(_ context.Context, m *dbus.Message) ([]any, error) {
			if m.Flags&dbus.FlagAllowInteractiveAuthorization == 0 {
				return nil, dbus.NewError("org.freedesktop.DBus.Error.InteractiveAuthorizationRequired", "no prompt allowed")
			}
			f.mu.Lock()
			defer f.mu.Unlock()
			f.props[prop] = m.Body[0]
			f.calls = append(f.calls, m.Member+" "+m.Body[0].(string))
			return nil, nil
		}}
	}
	if _, err := conn.Export(user, dbus.Interface{Name: userIface, Methods: map[string]dbus.Method{
		"SetIconFile": setter("IconFile"), "SetRealName": setter("RealName"),
	}}); err != nil {
		t.Fatal(err)
	}
	if _, err := conn.Export(user, dbus.Interface{Name: "org.freedesktop.DBus.Properties", Methods: map[string]dbus.Method{
		"GetAll": {In: "s", Out: "a{sv}", Fn: func(context.Context, *dbus.Message) ([]any, error) {
			f.mu.Lock()
			defer f.mu.Unlock()
			out := map[string]dbus.Variant{}
			for k, v := range f.props {
				out[k] = dbus.MakeVariant(v)
			}
			return []any{out}, nil
		}},
	}}); err != nil {
		t.Fatal(err)
	}
	if _, err := conn.RequestName(ctx(t), accountsBus, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	return f
}

func TestAccountsService(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	f := newFakeAccounts(t, bus)
	home := t.TempDir()
	a := New(Options{UID: 1000, Login: "me", Home: home, Root: t.TempDir(), SystemBus: func(ctx context.Context) (*dbus.Conn, error) {
		return dbus.Dial(ctx, bus.Address, dbus.Options{})
	}})
	if got, want := a.Get(ctx(t)), (Account{Login: "me", RealName: "Travis", Admin: true, Accounts: true}); got != want {
		t.Fatalf("Get = %+v, want %+v", got, want)
	}
	// A wide picture: its middle square, scaled down
	pic := filepath.Join(t.TempDir(), "wide.png")
	img := image.NewRGBA(image.Rect(0, 0, 800, 400))
	for x := 200; x < 600; x++ {
		for y := 0; y < 400; y++ {
			img.Set(x, y, color.RGBA{255, 0, 0, 255})
		}
	}
	out, _ := os.Create(pic)
	png.Encode(out, img)
	out.Close()
	got, err := a.SetIcon(ctx(t), pic)
	if err != nil {
		t.Fatal(err)
	}
	face := filepath.Join(home, ".face")
	if got.Icon != face {
		t.Errorf("the picture is %q, want ~/.face", got.Icon)
	}
	saved, err := os.Open(face)
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := png.Decode(saved)
	saved.Close()
	if err != nil {
		t.Fatal(err)
	}
	if b := decoded.Bounds(); b.Dx() != pictureSize || b.Dy() != pictureSize {
		t.Errorf("~/.face is %v, want %d px square", b, pictureSize)
	}
	if r, _, _, _ := decoded.At(pictureSize/2, pictureSize/2).RGBA(); r>>8 != 255 {
		t.Error("~/.face isn't the picture's middle")
	}
	if _, err := a.SetRealName(ctx(t), "Travis M"); err != nil {
		t.Fatal(err)
	}
	if _, err := a.SetRealName(ctx(t), "a:b"); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("a name with a colon: %v", err)
	}
	if _, err := a.SetIcon(ctx(t), filepath.Join(home, "missing.png")); axerr.KindOf(err) != axerr.NotFound {
		t.Errorf("a missing picture: %v", err)
	}
	notImage := filepath.Join(home, "notes.txt")
	write(t, notImage, "hello")
	if _, err := a.SetIcon(ctx(t), notImage); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("a text file as the picture: %v", err)
	}
	f.mu.Lock()
	calls := strings.Join(f.calls, "\n")
	f.mu.Unlock()
	if want := "SetIconFile " + face + "\nSetRealName Travis M"; calls != want {
		t.Errorf("calls:\n%s\nwant:\n%s", calls, want)
	}
}

// fakePasswd is a shell script asking as passwd does: the current
// password (right), then the new one twice; "weak" is refused as
// pam_pwquality refuses, asking again
const fakePasswd = `#!/bin/sh
echo "Changing password for me."
printf "Current password: "
read -r cur
if [ "$cur" != the-right-one ]; then
  echo "passwd: Authentication token manipulation error"
  echo "passwd: password unchanged"
  exit 10
fi
printf "New password: "
read -r new
if [ "$new" = weak ]; then
  echo "BAD PASSWORD: The password is shorter than 8 characters"
  printf "New password: "
  read -r new
fi
printf "Retype new password: "
read -r again
if [ "$new" != "$again" ]; then
  echo "Sorry, passwords do not match."
  echo "passwd: Authentication token manipulation error"
  exit 10
fi
echo "passwd: password updated successfully"
`

func TestChangePassword(t *testing.T) {
	t.Parallel()
	script := filepath.Join(t.TempDir(), "fake-passwd")
	write(t, script, fakePasswd)
	a := New(Options{Login: "me", Home: t.TempDir(), Passwd: []string{script}})
	for _, c := range []struct {
		current, next string
		want          PasswordResult
	}{
		{"the-right-one", "a-long-one", PasswordResult{OK: true}},
		{"not-it", "a-long-one", PasswordResult{Reason: ReasonWrong, Message: "The current password is wrong."}},
		{"the-right-one", "weak", PasswordResult{Reason: ReasonWeak, Message: "The password is shorter than 8 characters"}},
		{"the-right-one", "", PasswordResult{Reason: ReasonWeak, Message: "The new password is empty."}},
	} {
		got, err := a.ChangePassword(ctx(t), c.current, c.next)
		if err != nil {
			t.Fatalf("%q → %q: %v", c.current, c.next, err)
		}
		if got != c.want {
			t.Errorf("%q → %q: %+v, want %+v", c.current, c.next, got, c.want)
		}
		if strings.Contains(got.Message, c.current) && c.current != "" || c.next != "" && strings.Contains(got.Message, c.next) && c.next != "weak" {
			t.Errorf("a password shows in the message %q", got.Message)
		}
	}
	if _, err := a.ChangePassword(ctx(t), "the-right-one", "two\nlines"); axerr.KindOf(err) != axerr.BadRequest {
		t.Errorf("a new line in a password: %v", err)
	}
}

func TestChangePasswordHangs(t *testing.T) {
	t.Parallel()
	script := filepath.Join(t.TempDir(), "silent-passwd")
	write(t, script, "#!/bin/sh\nsleep 30\n")
	a := New(Options{Login: "me", Home: t.TempDir(), Passwd: []string{script}, PasswordTimeout: 300 * time.Millisecond})
	got, err := a.ChangePassword(ctx(t), "right", "new-one")
	if err != nil || got.OK || got.Reason != ReasonFailed {
		t.Errorf("a passwd that never asks: %+v, %v", got, err)
	}
}
