package screenshare

import (
	"reflect"
	"testing"
)

func TestXDPHRequest(t *testing.T) {
	t.Parallel()
	env := map[string]string{
		// As xdph 1.5.0 builds them (buildOutputList, buildWindowList); a
		// name may hold a colon, a title [HC>]-like text is sanitized
		XDPHOutputsVar: "4:DP-1:0:0:2560:1440;10:HDMI-A-1:x:2560:0:1920:1080;",
		XDPHWindowsVar: "4294967295[HC>]kitty[HT>]Terminal[HE>]94372781522144[HA>]12[HC>]firefox[HT>]A (b) c[HE>]0[HA>]broken[HC>]",
	}
	got := XDPHRequest(func(k string) string { return env[k] })
	want := Request{
		Backend: BackendXDPH, Region: true,
		Outputs: []Output{{Name: "DP-1"}, {Name: "HDMI-A-1:x"}},
		Windows: []Window{
			{Token: "4294967295", ID: "0x55d4e01e7ce0", Title: "Terminal", AppID: "kitty"},
			{Token: "12", Title: "A (b) c", AppID: "firefox"},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got  %+v\nwant %+v", got, want)
	}
	if empty := XDPHRequest(func(string) string { return "" }); len(empty.Outputs) != 0 || len(empty.Windows) != 0 || empty.Outputs == nil {
		t.Errorf("nothing offered: %+v", empty)
	}
}

func TestXDPHSelection(t *testing.T) {
	t.Parallel()
	r := Request{Backend: BackendXDPH, Region: true, Outputs: []Output{{Name: "DP-1"}}, Windows: []Window{{Token: "12"}}}
	cases := []struct {
		choice   *Choice
		remember bool
		want     string
	}{
		{&Choice{Kind: KindScreen, Output: "DP-1"}, true, "[SELECTION]r/screen:DP-1\n"},
		{&Choice{Kind: KindScreen, Output: "DP-1"}, false, "[SELECTION]/screen:DP-1\n"},
		{&Choice{Kind: KindWindow, Window: "12"}, true, "[SELECTION]r/window:12\n"},
		{&Choice{Kind: KindRegion, Output: "DP-1", Rect: &Rect{X: 20, Y: 30, W: 800, H: 600}}, false, "[SELECTION]/region:DP-1@20,30,800,600\n"},
		{nil, true, ""},
		{&Choice{Kind: KindScreen, Output: "HDMI-A-1"}, true, ""},
		{&Choice{Kind: KindWindow, Window: "13"}, true, ""},
		{&Choice{Kind: KindRegion, Output: "DP-1", Rect: &Rect{W: 0, H: 10}}, true, ""},
		{&Choice{Kind: KindRegion, Output: "DP-1"}, true, ""},
	}
	for _, tc := range cases {
		if got := XDPHSelection(r, tc.choice, tc.remember); got != tc.want {
			t.Errorf("%+v: got %q, want %q", tc.choice, got, tc.want)
		}
	}
}

func TestXDPHPicker(t *testing.T) {
	t.Parallel()
	set := func(k string) string {
		if k == XDPHOutputsVar {
			return "4:DP-1:0:0:1:1;"
		}
		return ""
	}
	cases := []struct {
		args   []string
		getenv func(string) string
		want   bool
	}{
		{nil, set, true},
		{[]string{"--allow-token"}, set, true},
		{[]string{"ping"}, set, false},
		{nil, func(string) string { return "" }, false},
	}
	for _, tc := range cases {
		if got := XDPHPicker(tc.args, tc.getenv); got != tc.want {
			t.Errorf("%v: got %v", tc.args, got)
		}
	}
}

func TestXDPW(t *testing.T) {
	t.Parallel()
	lines := []string{
		"Monitor: DP-1 Dell Inc. U2720Q",
		"Monitor: HDMI-A-1",
		"Window: A (b) c (3f2a)",
		"Window: 77b1",
		"something else",
	}
	r, labels := XDPWRequest(lines)
	want := Request{
		Backend: BackendXDPW,
		Outputs: []Output{{Name: "DP-1", Label: "Dell Inc. U2720Q"}, {Name: "HDMI-A-1"}},
		Windows: []Window{{Token: "3f2a", Title: "A (b) c"}, {Token: "77b1"}},
	}
	if !reflect.DeepEqual(r, want) {
		t.Errorf("got  %+v\nwant %+v", r, want)
	}
	cases := []struct {
		choice *Choice
		want   string
	}{
		{&Choice{Kind: KindScreen, Output: "DP-1"}, lines[0]},
		{&Choice{Kind: KindWindow, Window: "3f2a"}, lines[2]},
		{&Choice{Kind: KindWindow, Window: "77b1"}, lines[3]},
		{&Choice{Kind: KindScreen, Output: "eDP-1"}, ""},
		{&Choice{Kind: KindRegion, Output: "DP-1", Rect: &Rect{W: 1, H: 1}}, ""},
		{nil, ""},
	}
	for _, tc := range cases {
		if got := XDPWLabel(labels, tc.choice); got != tc.want {
			t.Errorf("%+v: got %q, want %q", tc.choice, got, tc.want)
		}
	}
	if got := XDPWMonitorLabel(labels, "HDMI-A-1\n"); got != lines[1] {
		t.Errorf("slurp's answer: %q", got)
	}
}
