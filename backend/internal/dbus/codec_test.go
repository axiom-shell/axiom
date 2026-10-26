package dbus

import (
	"encoding/hex"
	"reflect"
	"strings"
	"testing"
)

func TestMarshalBytes(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		sig  string
		args []any
		hex  string
	}{
		{"uint32", "u", []any{uint32(1)}, "01000000"},
		{"an int for a uint32", "u", []any{7}, "07000000"},
		{"byte then uint32 aligns", "yu", []any{uint8(1), uint32(2)}, "01000000" + "02000000"},
		{"string", "s", []any{"ab"}, "02000000" + "616200"},
		{"signature", "g", []any{Signature("as")}, "02" + "617300"},
		{"bool", "b", []any{true}, "01000000"},
		{"int16 then int64", "nx", []any{int16(-1), int64(2)}, "ffff" + "000000000000" + "0200000000000000"},
		{"byte array", "ay", []any{[]byte{1, 2}}, "02000000" + "0102"},
		// An empty array still pads to its element's alignment
		{"empty struct array", "a(i)", []any{[]any{}}, "00000000" + "00000000"},
		{"struct", "(yu)", []any{[]any{uint8(1), uint32(2)}}, "01000000" + "02000000"},
		{"variant", "v", []any{Variant{Sig: "u", Value: uint32(5)}}, "01" + "7500" + "00" + "05000000"},
		{"a{sv}", "a{sv}", []any{map[string]Variant{"a": {Sig: "y", Value: uint8(9)}}},
			"0a000000" + "00000000" + "01000000" + "6100" + "01" + "7900" + "09"},
		{"descriptor index", "hh", []any{UnixFD(10), UnixFD(11)}, "00000000" + "01000000"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			b, _, err := Marshal(c.sig, c.args...)
			if err != nil {
				t.Fatal(err)
			}
			if got := hex.EncodeToString(b); got != c.hex {
				t.Errorf("got  %s\nwant %s", got, c.hex)
			}
		})
	}
}

func TestRoundTrip(t *testing.T) {
	t.Parallel()
	cases := []struct {
		sig  string
		args []any
	}{
		{"ybnqiuxtd", []any{uint8(1), true, int16(-3), uint16(4), int32(-5), uint32(6), int64(-7), uint64(8), 9.5}},
		{"sog", []any{"héllo", ObjectPath("/org/a/b"), Signature("a{sv}")}},
		{"as", []any{[]string{"a", "", "c"}}},
		{"ao", []any{[]ObjectPath{"/a", "/b"}}},
		{"a{sv}", []any{map[string]Variant{"x": {Sig: "as", Value: []string{"y"}}, "n": {Sig: "t", Value: uint64(3)}}}},
		{"a{us}", []any{map[any]any{uint32(1): "one", uint32(2): "two"}}},
		{"a(su)", []any{[]any{[]any{"a", uint32(1)}, []any{"b", uint32(2)}}}},
		{"v", []any{Variant{Sig: "v", Value: Variant{Sig: "s", Value: "deep"}}}},
		{"aay", []any{[]any{[]byte{1}, []byte{}}}},
		{"h", []any{UnixFD(0)}},
	}
	for _, c := range cases {
		t.Run(c.sig, func(t *testing.T) {
			t.Parallel()
			b, _, err := Marshal(c.sig, c.args...)
			if err != nil {
				t.Fatal(err)
			}
			got, err := Unmarshal(c.sig, b, 1)
			if err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(got, c.args) {
				t.Errorf("got %#v\nwant %#v", got, c.args)
			}
		})
	}
}

func TestMarshalRefuses(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		sig  string
		args []any
	}{
		{"too few values", "su", []any{"a"}},
		{"a string for a uint", "u", []any{"1"}},
		{"out of range", "y", []any{256}},
		{"negative for unsigned", "u", []any{-1}},
		{"a bad object path", "o", []any{ObjectPath("/a//b")}},
		{"NUL in a string", "s", []any{"a\x00b"}},
		{"a dict outside an array", "{sv}", []any{nil}},
		{"a non-basic dict key", "a{vs}", []any{map[any]any{}}},
		{"a variant of two types", "v", []any{Variant{Sig: "ss", Value: nil}}},
		{"an empty struct", "()", []any{[]any{}}},
		{"a struct of the wrong size", "(ss)", []any{[]any{"a"}}},
		{"arrays too deep", strings.Repeat("a", 33) + "y", []any{nil}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			if _, _, err := Marshal(c.sig, c.args...); err == nil {
				t.Error("accepted")
			}
		})
	}
}

func TestUnmarshalRefuses(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		sig  string
		hex  string
		fds  uint32
	}{
		{"short", "u", "0100", 0},
		{"a bool of 2", "b", "02000000", 0},
		{"an unterminated string", "s", "01000000" + "6161", 0},
		{"a descriptor not sent", "h", "00000000", 0},
		{"nonzero padding", "yu", "01ff0000" + "02000000", 0},
		{"an array longer than the data", "ay", "10000000" + "01", 0},
		{"an invalid object path", "o", "01000000" + "6100", 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			b, _ := hex.DecodeString(c.hex)
			if _, err := Unmarshal(c.sig, b, c.fds); err == nil {
				t.Error("accepted")
			}
		})
	}
}

func TestSignatureOf(t *testing.T) {
	t.Parallel()
	cases := []struct {
		v    any
		want Signature
	}{
		{uint32(1), "u"},
		{"s", "s"},
		{[]string{}, "as"},
		{map[string]Variant{}, "a{sv}"},
		{map[string][]int32{}, "a{sai}"},
		{ObjectPath("/"), "o"},
	}
	for _, c := range cases {
		if got, err := SignatureOf(c.v); err != nil || got != c.want {
			t.Errorf("%T: got %q, %v; want %q", c.v, got, err, c.want)
		}
	}
	if _, err := SignatureOf([]any{}); err == nil {
		t.Error("[]any has a signature")
	}
}

func TestSocketPaths(t *testing.T) {
	t.Parallel()
	cases := []struct {
		address string
		want    []string
		err     bool
	}{
		{"unix:path=/run/user/1000/bus", []string{"/run/user/1000/bus"}, false},
		{"unix:abstract=/tmp/dbus-x,guid=abc", []string{"@/tmp/dbus-x"}, false},
		{"tcp:host=x;unix:path=/a%20b", []string{"/a b"}, false},
		{"tcp:host=localhost,port=1", nil, true},
	}
	for _, c := range cases {
		got, err := socketPaths(c.address)
		if (err != nil) != c.err || !reflect.DeepEqual(got, c.want) {
			t.Errorf("%q: got %v, %v", c.address, got, err)
		}
	}
}

func TestValidPath(t *testing.T) {
	t.Parallel()
	for p, want := range map[string]bool{"/": true, "/a": true, "/a/b_1": true, "": false, "a": false, "/a/": false, "//": false, "/a-b": false} {
		if validPath(p) != want {
			t.Errorf("%q: got %v", p, !want)
		}
	}
}
