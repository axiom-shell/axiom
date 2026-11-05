package render

import (
	"reflect"
	"testing"

	"github.com/axiom-shell/axiom/backend/internal/jsonx"
)

// The input method's variables and command per framework, legacyApps'
// im modules, and the user's own framework autostart left out while axiom
// starts it.
func TestInputMethod(t *testing.T) {
	t.Parallel()
	im := func(framework string, legacy bool) *jsonx.Object {
		return jsonx.Obj("framework", framework, "autostart", true, "legacyApps", legacy)
	}
	names := func(env [][2]string) []string {
		var out []string
		for _, p := range env {
			out = append(out, p[0]+"="+p[1])
		}
		return out
	}
	if got := names(InputMethodEnv(im("ibus", true))); !reflect.DeepEqual(got, []string{"XMODIFIERS=@im=ibus", "QT_IM_MODULES=wayland;ibus",
		"SDL_IM_MODULE=ibus", "GLFW_IM_MODULE=ibus", "GTK_IM_MODULE=ibus", "QT_IM_MODULE=ibus"}) {
		t.Errorf("ibus with legacyApps: %v", got)
	}
	if got := names(InputMethodEnv(im("fcitx5", false))); len(got) != 4 || got[0] != "XMODIFIERS=@im=fcitx" {
		t.Errorf("fcitx5: %v", got)
	}
	if got := InputMethodEnv(im("", true)); len(got) != 0 {
		t.Errorf("none: %v", got)
	}
	if got := InputMethodCommand(im("ibus", false)); got != "ibus-daemon -drxR" {
		t.Errorf("ibus command %q", got)
	}
	if got := InputMethodCommand(jsonx.Obj("framework", "fcitx5", "autostart", false)); got != "" {
		t.Errorf("autostart off: %q", got)
	}
	// The user's own wins: a session variable of the same name
	env := SessionEnv(jsonx.Obj("env", jsonx.Arr(jsonx.Obj("name", "XMODIFIERS", "value", "@im=mine"))), nil,
		jsonx.Obj("inputMethod", im("fcitx5", false)))
	for _, e := range env.Items {
		if get(e, "name") == "XMODIFIERS" && get(e, "value") != "@im=mine" {
			t.Errorf("the session's XMODIFIERS lost: %v", get(e, "value"))
		}
	}
	entry := func(command string) *jsonx.Object { return jsonx.Obj("command", command, "enabled", true) }
	autostart := jsonx.Arr(entry("/usr/bin/fcitx5"), entry("'fcitx5' -d"), entry("fcitx5-configtool"), entry("nm-applet"))
	got := autostartCommands(autostart, jsonx.Obj("inputMethod", "fcitx5 -d --replace"), func(string) bool { return false })
	if !reflect.DeepEqual(got, []string{"fcitx5 -d --replace", "fcitx5-configtool", "nm-applet"}) {
		t.Errorf("autostart %v", got)
	}
	if got := autostartCommands(autostart, jsonx.Obj(), func(string) bool { return false }); len(got) != 4 {
		t.Errorf("without axiom's: %v", got)
	}
}

// The xkb layouts written: an engine's typing layout joins them only
// while Input.keyboard.method.enabled is on.
func TestXkbLayoutsFollowMethodEnabled(t *testing.T) {
	t.Parallel()
	schema := jsonx.Obj("properties", jsonx.Obj("sources", jsonx.Obj("x-compositor",
		jsonx.Obj("sway", jsonx.Arr(jsonx.Obj("key", "xkb_layout", "from", "xkbLayout"))))))
	for _, enabled := range []bool{false, true} {
		values := jsonx.Obj("sources", jsonx.Arr(
			jsonx.Obj("id", "us", "kind", "xkb", "layout", "us"),
			jsonx.Obj("id", "pinyin", "kind", "ime", "layout", "cn", "engine", "pinyin")),
			"method", jsonx.Obj("enabled", enabled))
		fields := CompositorFields(schema, values, "sway", "")
		want := map[bool]string{false: "us", true: "us,cn"}[enabled]
		if len(fields) != 1 || fields[0].Value != want {
			t.Errorf("method.enabled %v: %+v, want %q", enabled, fields, want)
		}
	}
}
