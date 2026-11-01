package lockkeys

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestRead(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		leds map[string]string // "<device>::<name>" → brightness ("" for no file)
		want State
	}{
		{"no LEDs", nil, State{}},
		{"caps off", map[string]string{"input2::capslock": "0\n", "input2::numlock": "0\n"}, State{Available: true}},
		{"caps on", map[string]string{"input2::capslock": "1\n"}, State{Available: true, Caps: true}},
		{"any keyboard lit", map[string]string{"input2::capslock": "0\n", "input5::capslock": "1\n", "input5::numlock": "1\n"}, State{Available: true, Caps: true, Num: true}},
		{"a max brightness above 1", map[string]string{"input2::capslock": "255\n", "input2::scrolllock": "1"}, State{Available: true, Caps: true, Scroll: true}},
		{"garbled or unreadable is off", map[string]string{"input2::capslock": "x\n", "input5::capslock": ""}, State{Available: true}},
		{"num lock alone isn't available", map[string]string{"input2::numlock": "1\n"}, State{Num: true}},
		{"other LEDs ignored", map[string]string{"enp9s0-0::lan": "1\n", "input2::compose": "1\n"}, State{}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			root := t.TempDir()
			for led, value := range tt.leds {
				dir := filepath.Join(root, led)
				if err := os.Mkdir(dir, 0o755); err != nil {
					t.Fatal(err)
				}
				if value == "" {
					continue
				}
				if err := os.WriteFile(filepath.Join(dir, "brightness"), []byte(value), 0o644); err != nil {
					t.Fatal(err)
				}
			}
			if got := Read(root); got != tt.want {
				t.Errorf("Read = %+v, want %+v", got, tt.want)
			}
		})
	}
}

func TestSourceFetches(t *testing.T) {
	t.Parallel()
	root := t.TempDir()
	if err := os.Mkdir(filepath.Join(root, "input2::capslock"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "input2::capslock", "brightness"), []byte("1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	src := Source(Options{Root: root})
	if src.Name != "lockKeys" || src.Floor <= 0 || src.Default < src.Floor {
		t.Fatalf("source = %q floor %v default %v", src.Name, src.Floor, src.Default)
	}
	got, err := src.Fetch(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	if got != (State{Available: true, Caps: true}) {
		t.Errorf("Fetch = %+v", got)
	}
}
