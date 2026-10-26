package dbus

import (
	"fmt"
	"reflect"
)

// The spec's limits (the D-Bus specification, "Valid Signatures" and
// "Message Format")
const (
	maxSignature  = 255
	maxArrayDepth = 32
	maxStructDep  = 32
	maxDepth      = 64 // containers nested, variants included, in a value
	maxArrayBytes = 64 << 20
	maxMessage    = 128 << 20
)

// ObjectPath is an object path (o).
type ObjectPath string

// Signature is a type signature (g).
type Signature string

// UnixFD is a file descriptor (h). Sent, it is the descriptor's number
// (still the caller's: the kernel duplicates it); received, it is the
// index into the message's Files (Message.File).
type UnixFD int32

// Variant is a value of any type (v), with its signature.
type Variant struct {
	Sig   Signature
	Value any
}

// MakeVariant wraps v in a variant, its signature from its Go type
// (MustSignatureOf).
func MakeVariant(v any) Variant {
	return Variant{Sig: MustSignatureOf(v), Value: v}
}

func (v Variant) String() string { return fmt.Sprintf("<%s %v>", v.Sig, v.Value) }

// SignatureOf is the signature of a Go value as this package encodes it:
// the basic types, ObjectPath, Signature, UnixFD, Variant, slices
// (arrays), maps (dicts) and []any is refused (its elements could differ).
func SignatureOf(v any) (Signature, error) {
	s, err := sigOf(reflect.TypeOf(v))
	return Signature(s), err
}

// MustSignatureOf is SignatureOf for types known to have one; it panics
// otherwise (a programming error).
func MustSignatureOf(v any) Signature {
	s, err := SignatureOf(v)
	if err != nil {
		panic(err)
	}
	return s
}

var (
	typeObjectPath = reflect.TypeOf(ObjectPath(""))
	typeSignature  = reflect.TypeOf(Signature(""))
	typeUnixFD     = reflect.TypeOf(UnixFD(0))
	typeVariant    = reflect.TypeOf(Variant{})
)

func sigOf(t reflect.Type) (string, error) {
	if t == nil {
		return "", fmt.Errorf("dbus: no signature for nil")
	}
	switch t {
	case typeObjectPath:
		return "o", nil
	case typeSignature:
		return "g", nil
	case typeUnixFD:
		return "h", nil
	case typeVariant:
		return "v", nil
	}
	switch t.Kind() {
	case reflect.Uint8:
		return "y", nil
	case reflect.Bool:
		return "b", nil
	case reflect.Int16:
		return "n", nil
	case reflect.Uint16:
		return "q", nil
	case reflect.Int32, reflect.Int:
		return "i", nil
	case reflect.Uint32, reflect.Uint:
		return "u", nil
	case reflect.Int64:
		return "x", nil
	case reflect.Uint64:
		return "t", nil
	case reflect.Float64, reflect.Float32:
		return "d", nil
	case reflect.String:
		return "s", nil
	case reflect.Slice, reflect.Array:
		if t.Elem().Kind() == reflect.Interface {
			return "", fmt.Errorf("dbus: no signature for %s", t)
		}
		elem, err := sigOf(t.Elem())
		return "a" + elem, err
	case reflect.Map:
		key, err := sigOf(t.Key())
		if err != nil {
			return "", err
		}
		if !isBasic(key[0]) {
			return "", fmt.Errorf("dbus: a dict key must be a basic type, not %s", t.Key())
		}
		val, err := sigOf(t.Elem())
		return "a{" + key + val + "}", err
	}
	return "", fmt.Errorf("dbus: no signature for %s", t)
}

func isBasic(c byte) bool {
	switch c {
	case 'y', 'b', 'n', 'q', 'i', 'u', 'x', 't', 'd', 's', 'o', 'g', 'h':
		return true
	}
	return false
}

// alignOf is a type's alignment, by its signature's first character.
func alignOf(c byte) int {
	switch c {
	case 'y', 'g', 'v':
		return 1
	case 'n', 'q':
		return 2
	case 'x', 't', 'd', '(', '{':
		return 8
	}
	return 4 // b i u s o h a
}

// splitSignature splits a signature into its complete types, checking it.
func splitSignature(s string) ([]string, error) {
	if len(s) > maxSignature {
		return nil, fmt.Errorf("dbus: signature longer than %d", maxSignature)
	}
	var out []string
	for rest := s; rest != ""; {
		n, err := completeType(rest, 0, 0)
		if err != nil {
			return nil, fmt.Errorf("dbus: signature %q: %w", s, err)
		}
		out = append(out, rest[:n])
		rest = rest[n:]
	}
	return out, nil
}

// singleType checks that s is one complete type.
func singleType(s string) error {
	types, err := splitSignature(s)
	if err != nil {
		return err
	}
	if len(types) != 1 {
		return fmt.Errorf("dbus: %q is not one complete type", s)
	}
	return nil
}

// completeType is the length of the complete type s starts with.
func completeType(s string, arrays, structs int) (int, error) {
	if s == "" {
		return 0, fmt.Errorf("ends early")
	}
	c := s[0]
	switch {
	case isBasic(c), c == 'v':
		return 1, nil
	case c == 'a':
		if arrays+1 > maxArrayDepth {
			return 0, fmt.Errorf("arrays nested deeper than %d", maxArrayDepth)
		}
		if len(s) > 1 && s[1] == '{' {
			n, err := dictEntry(s[1:], arrays+1, structs)
			return n + 1, err
		}
		n, err := completeType(s[1:], arrays+1, structs)
		return n + 1, err
	case c == '(':
		if structs+1 > maxStructDep {
			return 0, fmt.Errorf("structs nested deeper than %d", maxStructDep)
		}
		i := 1
		for {
			if i >= len(s) {
				return 0, fmt.Errorf("a struct isn't closed")
			}
			if s[i] == ')' {
				if i == 1 {
					return 0, fmt.Errorf("an empty struct")
				}
				return i + 1, nil
			}
			n, err := completeType(s[i:], arrays, structs+1)
			if err != nil {
				return 0, err
			}
			i += n
		}
	case c == '{':
		return 0, fmt.Errorf("a dict entry outside an array")
	}
	return 0, fmt.Errorf("unknown type %q", c)
}

// dictEntry is the length of the {kv} s starts with.
func dictEntry(s string, arrays, structs int) (int, error) {
	if structs+1 > maxStructDep {
		return 0, fmt.Errorf("structs nested deeper than %d", maxStructDep)
	}
	if len(s) < 4 || !isBasic(s[1]) {
		return 0, fmt.Errorf("a dict key must be a basic type")
	}
	n, err := completeType(s[2:], arrays, structs+1)
	if err != nil {
		return 0, err
	}
	end := 2 + n
	if end >= len(s) || s[end] != '}' {
		return 0, fmt.Errorf("a dict entry holds a key and one value")
	}
	return end + 1, nil
}

// validPath checks an object path: /, or /-separated [A-Za-z0-9_]+.
func validPath(p string) bool {
	if p == "/" {
		return true
	}
	if len(p) < 2 || p[0] != '/' || p[len(p)-1] == '/' {
		return false
	}
	prev := byte('/')
	for i := 1; i < len(p); i++ {
		c := p[i]
		switch {
		case c == '/':
			if prev == '/' {
				return false
			}
		case c >= 'A' && c <= 'Z', c >= 'a' && c <= 'z', c >= '0' && c <= '9', c == '_':
		default:
			return false
		}
		prev = c
	}
	return true
}
