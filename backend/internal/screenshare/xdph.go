package screenshare

import (
	"strconv"
	"strings"
)

// xdg-desktop-portal-hyprland runs its picker (screencopy's
// custom_picker_binary) with what can be shared in its environment, and
// reads the choice from its output: `[SELECTION]<flags>/<target>`, flag r
// letting the app keep a restore token; no [SELECTION] line is a cancel.
// (xdph 1.5.0, src/shared/ScreencopyShared.cpp.)

// The environment variables xdph sets for its picker
const (
	XDPHOutputsVar = "XDPH_OUTPUT_SHARING_LIST"
	XDPHWindowsVar = "XDPH_WINDOW_SHARING_LIST"
)

// XDPHRequest is the request xdph's picker environment offers (outputs
// `<len>:<name>:<x>:<y>:<w>:<h>;` each, windows
// `<handle>[HC>]<class>[HT>]<title>[HE>]<address>[HA>]` each, the address
// Hyprland's in decimal).
func XDPHRequest(getenv func(string) string) Request {
	r := Request{Backend: BackendXDPH, Region: true, Outputs: []Output{}, Windows: []Window{}}
	outs := getenv(XDPHOutputsVar)
	for outs != "" {
		colon := strings.IndexByte(outs, ':')
		if colon < 0 {
			break
		}
		n, err := strconv.Atoi(outs[:colon])
		if err != nil || n <= 0 || colon+1+n > len(outs) {
			break
		}
		r.Outputs = append(r.Outputs, Output{Name: outs[colon+1 : colon+1+n]})
		rest := outs[colon+1+n:]
		end := strings.IndexByte(rest, ';')
		if end < 0 {
			break
		}
		outs = rest[end+1:]
	}
	for _, rec := range strings.Split(getenv(XDPHWindowsVar), "[HA>]") {
		handle, rest, ok := strings.Cut(rec, "[HC>]")
		if !ok {
			continue
		}
		class, rest, ok := strings.Cut(rest, "[HT>]")
		if !ok {
			continue
		}
		title, addr, ok := strings.Cut(rest, "[HE>]")
		if !ok {
			continue
		}
		if _, err := strconv.ParseUint(handle, 10, 32); err != nil {
			continue
		}
		w := Window{Token: handle, Title: title, AppID: class}
		if a, err := strconv.ParseUint(addr, 10, 64); err == nil && a != 0 {
			w.ID = "0x" + strconv.FormatUint(a, 16)
		}
		r.Windows = append(r.Windows, w)
	}
	return r
}

// XDPHSelection is the line xdph reads for c; remember lets the app keep
// a restore token. A choice r doesn't offer is "" (a cancel).
func XDPHSelection(r Request, c *Choice, remember bool) string {
	if c == nil || !c.valid(r) {
		return ""
	}
	flags := ""
	if remember {
		flags = "r"
	}
	out := "[SELECTION]" + flags + "/"
	switch c.Kind {
	case KindScreen:
		return out + "screen:" + c.Output + "\n"
	case KindWindow:
		return out + "window:" + c.Window + "\n"
	default:
		return out + "region:" + c.Output + "@" + strconv.Itoa(c.Rect.X) + "," + strconv.Itoa(c.Rect.Y) + "," + strconv.Itoa(c.Rect.W) + "," + strconv.Itoa(c.Rect.H) + "\n"
	}
}

// XDPHPicker reports whether this process was started as xdph's picker:
// its environment has the lists, and its arguments are xdph's
// (--allow-token at most).
func XDPHPicker(args []string, getenv func(string) string) bool {
	if getenv(XDPHOutputsVar) == "" {
		return false
	}
	for _, a := range args {
		if a != "--allow-token" {
			return false
		}
	}
	return true
}
