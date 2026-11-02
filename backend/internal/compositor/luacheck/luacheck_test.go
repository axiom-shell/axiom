package luacheck

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"testing"
)

func TestParses(t *testing.T) {
	t.Parallel()
	standIn := Checker{LookPath: func(string) (string, error) { return "", errors.New("none") }}
	cases := []struct {
		name, src    string
		luac, gopher bool
	}{
		{"a chunk", "local x = 1\nhl.bind(\"SUPER + Q\", function() end)\n", true, true},
		{"an unclosed function", "hl.on(\"x\", function()\n", false, false},
		// Lua 5.4 only: luac (Hyprland's Lua) takes it, the stand-in doesn't
		{"integer division", "local x = 7 // 2\n", true, false},
	}
	_, err := exec.LookPath("luac")
	hasLuac := err == nil
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			if got := standIn.Parses(context.Background(), c.src); got != c.gopher {
				t.Errorf("stand-in: got %v, want %v", got, c.gopher)
			}
			if hasLuac {
				if got := (Checker{}).Parses(context.Background(), c.src); got != c.luac {
					t.Errorf("luac: got %v, want %v", got, c.luac)
				}
			}
		})
	}
}

func TestWholeLines(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name, src string
		line      int
		want      bool
	}{
		{"a call", "a()\nhl.exec_cmd(\"axiom run\")\nb()\n", 2, true},
		{"a block opened and closed", "hl.on(\"x\", function() hl.exec_cmd(\"axiom run\") end) -- axiom\n", 1, true},
		{"5.4's syntax around it", "local x <const> = 7 // 2\nhl.exec_cmd(\"axiom run\")\nlocal y = x >> 1\n", 2, true},
		{"inside a call over lines", "hl.exec_cmd(\n\"axiom run\")\n", 2, false},
		{"opens a call", "hl.exec_cmd(\n\"axiom run\")\n", 1, false},
		{"inside a function", "hl.on(\"x\", function()\n  hl.exec_cmd(\"axiom run\") end)\n", 2, false},
		{"inside a long string", "local s = [[\naxiom run\n]]\n", 2, false},
		{"opens a long comment", "a() --[[\naxiom run ]]\n", 1, false},
		{"a line comment after it", "a() -- (axiom run)\n", 1, true},
		{"an if's middle", "if x then\nelse a() end\n", 2, false},
		{"a whole if", "if x then a() else b() end\n", 1, true},
		{"a string holding brackets", "a(\")\")\n", 1, true},
		{"past the end", "a()\n", 3, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			if got := WholeLines(c.src, []int{c.line}); got != c.want {
				t.Errorf("got %v, want %v", got, c.want)
			}
		})
	}
}

func TestInCode(t *testing.T) {
	t.Parallel()
	src := "a([[\nx\n]])\n--[==[\ny ]==] b()\n-- c\n\"d\\\ne\"\n"
	want := []bool{true, false, false, true, false, true, true, false, true}
	got := InCode(src)
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}
