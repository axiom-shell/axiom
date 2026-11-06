package cli

import (
	"bytes"
	"context"
	"testing"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/dbus/dbustest"
	"github.com/axiom-shell/axiom/backend/internal/screenshare"
	"github.com/axiom-shell/axiom/backend/internal/testkit"
)

// portal-wait returns once the daemon takes the portal's name
func TestPortalWait(t *testing.T) {
	t.Parallel()
	bus := dbustest.New(t)
	daemon, err := dbus.Dial(context.Background(), bus.Address, dbus.Options{})
	if err != nil {
		t.Fatal(err)
	}
	defer daemon.Close()
	env := map[string]string{"DBUS_SESSION_BUS_ADDRESS": bus.Address}
	done := make(chan int, 1)
	go func() {
		var out bytes.Buffer
		done <- Run(context.Background(), Root(), []string{"portal-wait"}, &Env{Stdout: &out, Stderr: &out, Getenv: func(k string) string { return env[k] }})
	}()
	select {
	case code := <-done:
		t.Fatalf("returned %d before the name was taken", code)
	case <-time.After(200 * time.Millisecond):
	}
	if _, err := daemon.RequestName(context.Background(), screenshare.PortalBusName, dbus.NameDoNotQueue); err != nil {
		t.Fatal(err)
	}
	select {
	case code := <-done:
		if code != 0 {
			t.Errorf("exit %d", code)
		}
	case <-time.After(testkit.Bound(5 * time.Second)):
		t.Fatal("still waiting after the name was taken")
	}
}
