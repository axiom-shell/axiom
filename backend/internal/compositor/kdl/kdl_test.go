package kdl

import (
	"fmt"
	"testing"
)

func TestParse(t *testing.T) {
	t.Parallel()
	nodes, err := Parse("a 1 2.5 #true null \"s\\\"q\" r#\"raw\"# key=\"v\" /- gone /- x=1 { b; c 3 }; d \\\n  5\n" +
		"/-e { f }\n/* x /* nested */ */ g 0x1f \"multi\\nline\"")
	if err != nil {
		t.Fatal(err)
	}
	got := ""
	for _, n := range nodes {
		got += fmt.Sprintf("%s%v;", n.Name, n.Args)
	}
	if want := "a[1 2.5 true <nil> s\"q raw];d[5];g[31 multi\nline];"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
	if v, _ := nodes[0].Props.Get("key"); v != "v" || nodes[0].Props.Len() != 1 {
		t.Errorf("props %v", nodes[0].Props)
	}
	if len(nodes[0].Children) != 2 || nodes[0].Children[0].Name != "b" || nodes[0].Children[1].Name != "c" {
		t.Errorf("children %v", nodes[0].Children)
	}
	if nodes[2].Line != 4 || nodes[2].Col != 21 {
		t.Errorf("g at %d:%d", nodes[2].Line, nodes[2].Col)
	}
}

func TestParseErrors(t *testing.T) {
	t.Parallel()
	for _, text := range []string{"a {", "binds {\n", "a \"open", "}", "a 012", "a \\ b"} {
		if _, err := Parse(text); err == nil {
			t.Errorf("%q parsed", text)
		}
	}
}

// Columns count characters, as the bind merge's edits do
func TestColumnsAreCharacters(t *testing.T) {
	t.Parallel()
	nodes, err := Parse("binds {\n    /* é */ Mod+Q { close-window; }\n}\n")
	if err != nil {
		t.Fatal(err)
	}
	bind := nodes[0].Children[0]
	if bind.Line != 2 || bind.Col != 12 {
		t.Errorf("at %d:%d", bind.Line, bind.Col)
	}
}

func TestStrings(t *testing.T) {
	t.Parallel()
	nodes, err := Parse("a \"\\u{e9}\\s\" \"\"\"\n    one\n      two\n    \"\"\" #\"x\"y\"# r\"\\n\" \"a\\\n   b\"")
	if err != nil {
		t.Fatal(err)
	}
	want := []any{"é ", "one\n  two", `x"y`, `\n`, "ab"}
	if fmt.Sprint(nodes[0].Args) != fmt.Sprint(want) {
		t.Errorf("got %q", nodes[0].Args)
	}
}
