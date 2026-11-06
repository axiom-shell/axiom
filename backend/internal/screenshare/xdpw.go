package screenshare

import (
	"strings"
)

// xdg-desktop-portal-wlr's dmenu chooser (chooser_type=dmenu) gets what can
// be shared on its standard input, a label a line (`Monitor: <name>
// <description>`, `Window: <title> (<identifier>)`), and answers with the
// label picked; nothing is a cancel. (xdpw 0.8.5,
// src/screencast/chooser.c.)

const (
	xdpwMonitor = "Monitor: "
	xdpwWindow  = "Window: "
)

// XDPWRequest is the request in xdpw's labels, and the labels by token
// (a monitor's name, a window's identifier) to answer with.
func XDPWRequest(lines []string) (Request, map[string]string) {
	r := Request{Backend: BackendXDPW, Outputs: []Output{}, Windows: []Window{}}
	labels := map[string]string{}
	for _, line := range lines {
		switch {
		case strings.HasPrefix(line, xdpwMonitor):
			name, desc, _ := strings.Cut(strings.TrimPrefix(line, xdpwMonitor), " ")
			if name == "" {
				continue
			}
			r.Outputs = append(r.Outputs, Output{Name: name, Label: desc})
			labels["screen:"+name] = line
		case strings.HasPrefix(line, xdpwWindow):
			rest := strings.TrimPrefix(line, xdpwWindow)
			// The identifier is in the last parentheses; a title can hold
			// some of its own
			title, id := rest, rest
			if open := strings.LastIndex(rest, " ("); open >= 0 && strings.HasSuffix(rest, ")") {
				title, id = rest[:open], rest[open+2:len(rest)-1]
			} else {
				// No title: the label is the identifier alone
				title = ""
			}
			if id == "" {
				continue
			}
			r.Windows = append(r.Windows, Window{Token: id, Title: title})
			labels["window:"+id] = line
		}
	}
	return r, labels
}

// XDPWLabel is the label xdpw reads for c ("" for a cancel, or a choice
// it doesn't offer).
func XDPWLabel(labels map[string]string, c *Choice) string {
	if c == nil {
		return ""
	}
	switch c.Kind {
	case KindScreen:
		return labels["screen:"+c.Output]
	case KindWindow:
		return labels["window:"+c.Window]
	}
	return ""
}

// XDPWMonitorLabel is the label of the monitor named name, for a picker
// that answers with a monitor's name alone (slurp's).
func XDPWMonitorLabel(labels map[string]string, name string) string {
	return labels["screen:"+strings.TrimSpace(name)]
}
