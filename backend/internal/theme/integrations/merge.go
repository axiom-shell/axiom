package integrations

import (
	"bytes"
	"regexp"
	"slices"
	"strings"
)

// The lines ncspot's hookup puts in its config.toml's [theme] table (its
// x-hookup text); the colors go between them, as ncspot can't include a
// file
const (
	NcspotBegin = "# axiom theme: begin (rewritten on every theme change)"
	NcspotEnd   = "# axiom theme: end"
)

var (
	tomlSection = regexp.MustCompile(`^[ \t]*\[[ \t]*([^\]]*?)[ \t]*\]`)
	tomlKey     = regexp.MustCompile(`^[ \t]*([A-Za-z_]+)[ \t]*=`)
	blockKey    = regexp.MustCompile(`^([^=]*?)[ \t]*=`)
)

// SpliceNcspot puts the rendered colors between the markers in ncspot's
// config, leaving out the keys its [theme] sets outside them (own, which
// win). ok is false when the markers aren't there, once each, in [theme].
func SpliceNcspot(config, colors []byte) (out []byte, own []string, ok bool) {
	lines := splitLines(config)
	section, inside, markers, inTheme := "", false, 0, 0
	for _, line := range lines {
		if m := tomlSection.FindStringSubmatch(line); m != nil {
			section = m[1]
		}
		switch {
		case line == NcspotBegin:
			if section == "theme" {
				inTheme++
			}
			inside = true
			markers++
		case line == NcspotEnd:
			inside = false
			markers++
		case !inside && section == "theme":
			if m := tomlKey.FindStringSubmatch(line); m != nil {
				own = append(own, m[1])
			}
		}
	}
	if markers != 2 || inTheme != 1 {
		return nil, nil, false
	}
	var b strings.Builder
	inside = false
	for _, line := range lines {
		switch {
		case line == NcspotBegin:
			b.WriteString(line + "\n")
			for _, c := range splitLines(colors) {
				key := c
				if m := blockKey.FindStringSubmatch(c); m != nil {
					key = m[1]
				}
				if !slices.Contains(own, key) {
					b.WriteString(c + "\n")
				}
			}
			inside = true
			continue
		case line == NcspotEnd:
			inside = false
		}
		if !inside {
			b.WriteString(line + "\n")
		}
	}
	return []byte(b.String()), own, true
}

var (
	iniGroup = regexp.MustCompile(`^\[.*\]$`)
	iniKey   = regexp.MustCompile(`^[A-Za-z]+=`)
	blank    = regexp.MustCompile(`^[ \t]*$`)
	schemeAt = regexp.MustCompile(`^ColorScheme[ \t]*=[ \t]*(.*)$`)
)

// ColorSchemeIn is the ColorScheme a KDE config file sets in a group ("" for
// none).
func ColorSchemeIn(rc []byte, group string) string {
	here, value := false, ""
	for _, line := range splitLines(rc) {
		if strings.HasPrefix(line, "[") {
			here = line == "["+group+"]"
		} else if m := schemeAt.FindStringSubmatch(line); here && m != nil {
			value = m[1]
		}
	}
	return value
}

// MergeKDE is kdeglobals with the color scheme's groups but [General]
// copied in, as Plasma keeps them: each key the scheme sets replaced
// where it is, the ones missing added at the end of their group, and the
// groups missing at the end. Every other line stays.
func MergeKDE(scheme, kdeglobals []byte) []byte {
	type group struct {
		keys  []string
		lines map[string]string
	}
	groups := map[string]*group{}
	var order []string
	cur := ""
	for _, line := range splitLines(scheme) {
		if iniGroup.MatchString(line) {
			cur = line
			if cur == "[General]" {
				cur = ""
			} else if groups[cur] == nil {
				groups[cur] = &group{lines: map[string]string{}}
				order = append(order, cur)
			}
		} else if g := groups[cur]; g != nil && iniKey.MatchString(line) {
			k := line[:strings.IndexByte(line, '=')]
			if _, seen := g.lines[k]; !seen {
				g.keys = append(g.keys, k)
			}
			g.lines[k] = line
		}
	}

	var b strings.Builder
	done := map[string]bool{}
	present := map[string]bool{}
	blanks := 0
	flush := func() {
		if g := groups[cur]; g != nil {
			for _, k := range g.keys {
				if !done[cur+"\x00"+k] {
					b.WriteString(g.lines[k] + "\n")
					done[cur+"\x00"+k] = true
				}
			}
		}
	}
	blankLines := func() {
		b.WriteString(strings.Repeat("\n", blanks))
		blanks = 0
	}
	cur = ""
	for _, line := range splitLines(kdeglobals) {
		switch {
		case blank.MatchString(line):
			blanks++
			continue
		case strings.HasPrefix(line, "["):
			flush()
			blankLines()
			cur = line
			present[cur] = true
		default:
			blankLines()
			if i := strings.IndexByte(line, '='); i > 0 && groups[cur] != nil {
				if kv, ok := groups[cur].lines[line[:i]]; ok {
					line = kv
					done[cur+"\x00"+line[:i]] = true
				}
			}
		}
		b.WriteString(line + "\n")
	}
	flush()
	for _, name := range order {
		if present[name] {
			continue
		}
		b.WriteString("\n" + name + "\n")
		for _, k := range groups[name].keys {
			b.WriteString(groups[name].lines[k] + "\n")
		}
	}
	return []byte(b.String())
}

// FootStyle is the shape of colors an installed foot accepts.
type FootStyle int

const (
	// FootColors: foot 1.20's [colors] with the cursor in it (as rendered)
	FootColors FootStyle = iota
	// FootDarkLight: newer foots' [colors-dark] and [colors-light] (1.28
	// rejects [colors]); the theme goes in both
	FootDarkLight
	// FootCursorSection: older foots', the cursor in [cursor]
	FootCursorSection
)

// Foot reshapes the rendered foot.ini for a foot of that style.
func Foot(rendered []byte, style FootStyle) []byte {
	lines := splitLines(rendered)
	switch style {
	case FootDarkLight:
		i := 0
		for i < len(lines) && lines[i] != "[colors]" {
			i++
		}
		if i == len(lines) {
			return rendered
		}
		colors := strings.TrimRight(strings.Join(lines[i+1:], "\n"), "\n")
		head := strings.Join(lines[:i], "\n")
		if head != "" {
			head += "\n"
		}
		return []byte(head + "[colors-dark]\n" + colors + "\n\n[colors-light]\n" + colors + "\n")
	case FootCursorSection:
		var cursor string
		var rest strings.Builder
		for _, line := range lines {
			if v, ok := strings.CutPrefix(line, "cursor="); ok {
				cursor = v
				continue
			}
			rest.WriteString(line + "\n")
		}
		return []byte("[cursor]\ncolor=" + cursor + "\n\n" + rest.String())
	}
	return rendered
}

// splitLines is a file's lines, without the last one's newline.
func splitLines(b []byte) []string {
	b = bytes.TrimSuffix(b, []byte("\n"))
	if len(b) == 0 {
		return nil
	}
	return strings.Split(string(b), "\n")
}
