package xkb

import (
	"encoding/json"
	"os"
	"strings"
	"testing"
)

func TestParse(t *testing.T) {
	t.Parallel()
	f, err := os.Open("testdata/evdev.xml")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	reg, err := Parse(f)
	if err != nil {
		t.Fatal(err)
	}
	got, _ := json.Marshal(reg)
	want := `{"layouts":[` +
		`{"name":"us","short":"en","description":"English (US)","languages":["eng"],"variants":[` +
		`{"name":"dvorak","short":"","description":"English (Dvorak)","languages":[]},` +
		`{"name":"chr","short":"chr","description":"Cherokee","languages":["chr"]}]},` +
		`{"name":"de","short":"de","description":"German","languages":["ger"],"variants":[]}]}`
	if string(got) != want {
		t.Errorf("got  %s\nwant %s", got, want)
	}
}

func TestParseRefusesBrokenFiles(t *testing.T) {
	t.Parallel()
	for name, text := range map[string]string{
		"not xml":  "layouts",
		"cut off":  "<xkbConfigRegistry><layoutList><layout>",
		"no files": "",
	} {
		if _, err := Parse(strings.NewReader(text)); err == nil {
			t.Errorf("%s: no error", name)
		}
	}
	reg, err := Parse(strings.NewReader("<xkbConfigRegistry/>"))
	if err != nil || reg.Layouts == nil || len(reg.Layouts) != 0 {
		t.Errorf("an empty registry: %+v, %v", reg, err)
	}
}
