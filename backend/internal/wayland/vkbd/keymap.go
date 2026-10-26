package vkbd

import (
	"fmt"
	"strings"
	"unicode"
)

// firstKeycode is the first xkb keycode a keymap uses: xkb's are evdev's
// plus 8, and 8 itself is no key. lastKeycode keeps to what X11 clients
// (Xwayland) can take.
const (
	firstKeycode = 9
	lastKeycode  = 255
	perKeymap    = lastKeycode - firstKeycode + 1
)

// Chunk is part of a text and the keymap typing it: Keys are evdev codes
// (xkb keycode - 8), one per character typed.
type Chunk struct {
	Keymap string
	Keys   []uint32
}

// Plan splits text into chunks of at most 247 distinct characters, each
// with a keymap giving every one of them a key of its own. Control
// characters other than newline and tab are left out (they'd type
// nothing, or something unexpected).
func Plan(text string) []Chunk {
	var chunks []Chunk
	var syms []string
	codes := map[string]uint32{}
	var keys []uint32
	flush := func() {
		if len(keys) > 0 {
			chunks = append(chunks, Chunk{Keymap: keymap(syms), Keys: keys})
		}
		syms, codes, keys = nil, map[string]uint32{}, nil
	}
	for _, r := range text {
		sym, ok := keysym(r)
		if !ok {
			continue
		}
		code, seen := codes[sym]
		if !seen {
			if len(syms) == perKeymap {
				flush()
			}
			syms = append(syms, sym)
			code = uint32(firstKeycode + len(syms) - 1)
			codes[sym] = code
		}
		keys = append(keys, code-8)
	}
	flush()
	return chunks
}

// keysym is the xkb keysym name typing r: Unicode keysyms (U1F600),
// Return and Tab for newline and tab.
func keysym(r rune) (string, bool) {
	switch {
	case r == '\n':
		return "Return", true
	case r == '\t':
		return "Tab", true
	case r == unicode.ReplacementChar, unicode.IsControl(r):
		return "", false
	}
	return fmt.Sprintf("U%04X", r), true
}

// keymap is an xkb keymap with keycodes from 9 up for syms, in order (as
// wtype writes it).
func keymap(syms []string) string {
	var b strings.Builder
	b.WriteString("xkb_keymap {\nxkb_keycodes \"(unnamed)\" {\nminimum = 8;\n")
	fmt.Fprintf(&b, "maximum = %d;\n", firstKeycode+len(syms))
	for i := range syms {
		fmt.Fprintf(&b, "<K%d> = %d;\n", i+1, firstKeycode+i)
	}
	b.WriteString("};\nxkb_types \"(unnamed)\" { include \"complete\" };\n")
	b.WriteString("xkb_compatibility \"(unnamed)\" { include \"complete\" };\n")
	b.WriteString("xkb_symbols \"(unnamed)\" {\n")
	for i, s := range syms {
		fmt.Fprintf(&b, "key <K%d> {[%s]};\n", i+1, s)
	}
	b.WriteString("};\n};\n")
	return b.String()
}
