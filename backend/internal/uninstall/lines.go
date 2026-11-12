package uninstall

import (
	"bytes"
	"os"
	"regexp"
	"strings"

	"github.com/axiom-shell/axiom/backend/internal/compositor/edit"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
)

// The kinds of file Canonical knows the lines of.
const (
	kindHyprland = "hyprland"
	kindSway     = "sway"
	kindNiri     = "niri"
	kindXDPH     = "xdph" // xdg-desktop-portal-hyprland's xdph.conf
	kindXDPW     = "xdpw" // xdg-desktop-portal-wlr's config
)

// binary is the axiom binary a line names: any path or name whose
// basename is axiom, quoted as install.sh writes it ('…') or not.
const binary = `(?:'(?:[^'"]*/)?axiom'|(?:[^'"\s]*/)?axiom)`

// startsAxiom is install.sh's STARTS_AXIOM: a line that starts axiom
// (`axiom run`), however it is spelled.
var startsAxiom = regexp.MustCompile(`(^|[\s'"/])axiom['"]? +run([^[:alnum:]_-]|$)`)

// namesModule: a line naming a module axiom writes for a compositor.
var namesModule = regexp.MustCompile(`axiom/(hyprland\.lua|sway\.conf|niri\.kdl)`)

// mentionsAxiom is a portal config line that names axiom at all.
var mentionsAxiom = regexp.MustCompile(`(^|[\s'"/=:])axiom(['"\s]|$)`)

// canonical are the exact shapes, per kind: the lines install.sh and the
// writers add (one line each; a pair is two entries). The Hyprland start
// line also stands without its "-- axiom" mark, as the AUR package's notes
// tell users to add it.
var canonical = map[string][]*regexp.Regexp{
	kindHyprland: {
		regexp.MustCompile(`^hl\.on\("hyprland\.start", function\(\) hl\.exec_cmd\("` + binary + ` run"\) end\)(?: -- axiom)?$`),
		regexp.MustCompile(`^local ok, axiom = pcall\(dofile, "(?:[^"]*/)?axiom/hyprland\.lua"\)$`),
		regexp.MustCompile(`^if ok then axiom\.setup\(\) end$`),
	},
	kindSway: {
		regexp.MustCompile(`^exec ` + binary + ` run$`),
		regexp.MustCompile(`^include +(?:"[^"]*/axiom/sway\.conf"|'[^']*/axiom/sway\.conf'|[^\s"']*/axiom/sway\.conf)$`),
	},
	kindNiri: {
		regexp.MustCompile(`^spawn-sh-at-startup "` + binary + ` run"$`),
		regexp.MustCompile(`^include "[^"]*/axiom/niri\.kdl"$`),
	},
	kindXDPH: {
		regexp.MustCompile(`^screencopy:custom_picker_binary = ` + binary + `$`),
	},
	kindXDPW: {
		regexp.MustCompile(`^chooser_type = dmenu$`),
		regexp.MustCompile(`^chooser_cmd = ` + binary + ` screenshare-pick --for xdpw$`),
	},
}

// Canonical says whether line is exactly one of the lines axiom adds to a
// file of kind ("hyprland", "sway", "niri", "xdph", "xdpw"): install.sh's
// autostart line, the include lines the writers give, the screen-share
// picker's. Surrounding whitespace (and a CRLF) is allowed; nothing else:
// an exec_always, an extra argument, a comment, another program all are
// the user's.
func Canonical(kind, line string) bool {
	line = strings.TrimSpace(line)
	for _, re := range canonical[kind] {
		if re.MatchString(line) {
			// Every shape that starts axiom also is install.sh's pattern
			return !strings.Contains(line, " run") || startsAxiom.MatchString(line)
		}
	}
	return false
}

// Manual is a line of axiom's that the uninstall couldn't be sure was its
// own: it is left, and listed to remove by hand.
type Manual struct {
	File   string `json:"file"`
	Line   int    `json:"line"`
	Text   string `json:"text"`
	Reason string `json:"reason"`
}

// scan is what's in a file: the lines to remove (as indexes) and the ones
// to list.
type scan struct {
	Remove []int
	Manual []Manual
}

// scanFile reads the lines of data (the file at path, of kind). The
// hyprland include is a pair (its second line goes only with the first),
// so is the xdpw chooser (type, then command).
func scanFile(kind, path string, data []byte) scan {
	lines := splitKeep(string(data))
	var out scan
	remove := map[int]bool{}
	text := func(i int) string { return strings.TrimSpace(lines[i]) }
	canon := func(i int) bool { return i >= 0 && i < len(lines) && Canonical(kind, lines[i]) }
	for i := range lines {
		t := text(i)
		switch {
		case !canon(i):
		case kind == kindHyprland && strings.HasPrefix(t, "local ok, axiom = pcall"):
			remove[i] = true
			if canon(i+1) && text(i+1) == "if ok then axiom.setup() end" {
				remove[i+1] = true
			}
		case kind == kindHyprland && t == "if ok then axiom.setup() end":
			// Only with the line before it
		case kind == kindXDPW && strings.HasPrefix(t, "chooser_cmd"):
			if canon(i-1) && text(i-1) == "chooser_type = dmenu" {
				remove[i], remove[i-1] = true, true
			}
		case kind == kindXDPW:
			// chooser_type alone could be the user's own
		default:
			remove[i] = true
		}
	}
	for i := range lines {
		t := text(i)
		if t == "" || remove[i] {
			continue
		}
		reason := ""
		switch {
		case kind == kindHyprland && t == "if ok then axiom.setup() end" && canon(i):
			reason = "axiom's include of its module; the line above it is gone, remove this one too"
		case kind == kindXDPW && canon(i) && t == "chooser_type = dmenu":
			continue
		case kind == kindXDPW && canon(i):
			reason = "axiom's share picker, without the chooser_type line before it"
		case startsAxiom.MatchString(t):
			reason = "starts axiom, in a shape that isn't the one axiom writes"
		case namesModule.MatchString(t):
			reason = "loads axiom's module, in a shape that isn't the one axiom writes"
		case (kind == kindXDPH || kind == kindXDPW) && mentionsAxiom.MatchString(t):
			reason = "names axiom, in a shape that isn't the one axiom writes"
		default:
			continue
		}
		out.Manual = append(out.Manual, Manual{File: path, Line: i + 1, Text: t, Reason: reason})
	}
	for i := range lines {
		if remove[i] {
			out.Remove = append(out.Remove, i)
		}
	}
	return out
}

// splitKeep is data's lines, each with its line ending (the last has none
// when the text doesn't end in one).
func splitKeep(text string) []string {
	if text == "" {
		return nil
	}
	return strings.SplitAfter(strings.TrimSuffix(text, "\x00"), "\n")
}

// without is data with the lines at remove gone, every other byte kept.
func without(data []byte, remove []int) []byte {
	gone := map[int]bool{}
	for _, i := range remove {
		gone[i] = true
	}
	var out bytes.Buffer
	for i, l := range splitKeep(string(data)) {
		if !gone[i] {
			out.WriteString(l)
		}
	}
	return out.Bytes()
}

// removeLines takes the lines of path's canonical shape out, in place:
// through a symlink, the file keeps its mode. Nothing is written when
// nothing matches. It returns the lines it removed.
func removeLines(kind, path string) (removed []string, manual []Manual, err error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, err
	}
	s := scanFile(kind, path, data)
	if len(s.Remove) == 0 {
		return nil, s.Manual, nil
	}
	lines := splitKeep(string(data))
	for _, i := range s.Remove {
		removed = append(removed, strings.TrimSpace(lines[i]))
	}
	mode := os.FileMode(0o644)
	if info, err := os.Stat(path); err == nil {
		mode = info.Mode().Perm()
	}
	if err := edit.WriteMode(path, without(data, s.Remove), mode); err != nil {
		return nil, s.Manual, err
	}
	return removed, s.Manual, nil
}

// isFile: a regular file, a link followed.
func isFile(path string) bool { return fsx.IsFile(path) }
