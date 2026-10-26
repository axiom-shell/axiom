package dbus

import (
	"encoding/binary"
	"fmt"
	"math"
	"reflect"
	"sort"
	"strings"
	"unicode/utf8"
)

// encoder writes values in the wire format, little-endian. Offsets are
// from the start of its buffer, which starts 8-aligned in the message
// (the body does, and the header is the message's start).
type encoder struct {
	b     []byte
	fds   []int
	depth int
}

// Marshal encodes args by sig (the body of a message), returning the
// bytes and the descriptors they name.
func Marshal(sig string, args ...any) ([]byte, []int, error) {
	e := &encoder{}
	if err := e.values(sig, args); err != nil {
		return nil, nil, err
	}
	return e.b, e.fds, nil
}

func (e *encoder) values(sig string, args []any) error {
	types, err := splitSignature(sig)
	if err != nil {
		return err
	}
	if len(types) != len(args) {
		return fmt.Errorf("dbus: signature %q has %d values, got %d", sig, len(types), len(args))
	}
	for i, t := range types {
		if err := e.value(t, args[i]); err != nil {
			return err
		}
	}
	return nil
}

func (e *encoder) align(n int) {
	for len(e.b)%n != 0 {
		e.b = append(e.b, 0)
	}
}

func (e *encoder) u8(v uint8) { e.b = append(e.b, v) }
func (e *encoder) u16(v uint16) {
	e.align(2)
	e.b = binary.LittleEndian.AppendUint16(e.b, v)
}
func (e *encoder) u32(v uint32) {
	e.align(4)
	e.b = binary.LittleEndian.AppendUint32(e.b, v)
}
func (e *encoder) u64(v uint64) {
	e.align(8)
	e.b = binary.LittleEndian.AppendUint64(e.b, v)
}

func (e *encoder) str(s string) error {
	if !utf8.ValidString(s) || strings.IndexByte(s, 0) >= 0 {
		return fmt.Errorf("dbus: a string must be UTF-8 without NUL")
	}
	e.u32(uint32(len(s)))
	e.b = append(e.b, s...)
	e.b = append(e.b, 0)
	return nil
}

func (e *encoder) sig(s string) error {
	if _, err := splitSignature(s); err != nil {
		return err
	}
	e.u8(uint8(len(s)))
	e.b = append(e.b, s...)
	e.b = append(e.b, 0)
	return nil
}

// value encodes v as the complete type t.
func (e *encoder) value(t string, v any) error {
	switch t[0] {
	case 'y':
		n, err := asUint(v, math.MaxUint8)
		e.u8(uint8(n))
		return err
	case 'b':
		b, ok := v.(bool)
		if !ok {
			return mismatch(t, v)
		}
		var n uint32
		if b {
			n = 1
		}
		e.u32(n)
	case 'n':
		n, err := asInt(v, math.MinInt16, math.MaxInt16)
		e.u16(uint16(int16(n)))
		return err
	case 'q':
		n, err := asUint(v, math.MaxUint16)
		e.u16(uint16(n))
		return err
	case 'i':
		n, err := asInt(v, math.MinInt32, math.MaxInt32)
		e.u32(uint32(int32(n)))
		return err
	case 'u':
		n, err := asUint(v, math.MaxUint32)
		e.u32(uint32(n))
		return err
	case 'x':
		n, err := asInt(v, math.MinInt64, math.MaxInt64)
		e.u64(uint64(n))
		return err
	case 't':
		n, err := asUint(v, math.MaxUint64)
		e.u64(n)
		return err
	case 'd':
		var f float64
		switch x := v.(type) {
		case float64:
			f = x
		case float32:
			f = float64(x)
		default:
			return mismatch(t, v)
		}
		e.u64(math.Float64bits(f))
	case 's':
		s, ok := v.(string)
		if !ok {
			return mismatch(t, v)
		}
		return e.str(s)
	case 'o':
		var s string
		switch x := v.(type) {
		case ObjectPath:
			s = string(x)
		case string:
			s = x
		default:
			return mismatch(t, v)
		}
		if !validPath(s) {
			return fmt.Errorf("dbus: %q is not an object path", s)
		}
		return e.str(s)
	case 'g':
		var s string
		switch x := v.(type) {
		case Signature:
			s = string(x)
		case string:
			s = x
		default:
			return mismatch(t, v)
		}
		return e.sig(s)
	case 'h':
		fd, ok := v.(UnixFD)
		if !ok {
			return mismatch(t, v)
		}
		e.u32(uint32(len(e.fds)))
		e.fds = append(e.fds, int(fd))
	case 'v':
		vv, ok := v.(Variant)
		if !ok {
			return mismatch(t, v)
		}
		if err := singleType(string(vv.Sig)); err != nil {
			return err
		}
		if err := e.enter(); err != nil {
			return err
		}
		defer e.leave()
		if err := e.sig(string(vv.Sig)); err != nil {
			return err
		}
		return e.value(string(vv.Sig), vv.Value)
	case 'a':
		return e.array(t, v)
	case '(':
		return e.structure(t, v)
	default:
		return fmt.Errorf("dbus: can't encode %q", t)
	}
	return nil
}

func (e *encoder) enter() error {
	if e.depth++; e.depth > maxDepth {
		return fmt.Errorf("dbus: a value nested deeper than %d", maxDepth)
	}
	return nil
}

func (e *encoder) leave() { e.depth-- }

func (e *encoder) array(t string, v any) error {
	if err := e.enter(); err != nil {
		return err
	}
	defer e.leave()
	elem := t[1:]
	e.u32(0)
	lenAt := len(e.b) - 4
	e.align(alignOf(elem[0]))
	start := len(e.b)
	var err error
	if elem[0] == '{' {
		err = e.dict(elem, v)
	} else {
		err = e.slice(elem, v)
	}
	if err != nil {
		return err
	}
	n := len(e.b) - start
	if n > maxArrayBytes {
		return fmt.Errorf("dbus: an array of more than %d bytes", maxArrayBytes)
	}
	binary.LittleEndian.PutUint32(e.b[lenAt:], uint32(n))
	return nil
}

func (e *encoder) slice(elem string, v any) error {
	if b, ok := v.([]byte); ok && elem == "y" {
		e.b = append(e.b, b...)
		return nil
	}
	rv := reflect.ValueOf(v)
	if rv.Kind() != reflect.Slice && rv.Kind() != reflect.Array {
		return mismatch("a"+elem, v)
	}
	for i := 0; i < rv.Len(); i++ {
		if err := e.value(elem, rv.Index(i).Interface()); err != nil {
			return err
		}
	}
	return nil
}

// dict encodes a map as a{kv}, its keys sorted so the bytes are stable.
func (e *encoder) dict(entry string, v any) error {
	key, val := entry[1:2], entry[2:len(entry)-1]
	rv := reflect.ValueOf(v)
	if rv.Kind() != reflect.Map {
		return mismatch("a"+entry, v)
	}
	keys := rv.MapKeys()
	sort.Slice(keys, func(i, j int) bool { return fmt.Sprint(keys[i].Interface()) < fmt.Sprint(keys[j].Interface()) })
	for _, k := range keys {
		e.align(8)
		if err := e.value(key, k.Interface()); err != nil {
			return err
		}
		if err := e.value(val, rv.MapIndex(k).Interface()); err != nil {
			return err
		}
	}
	return nil
}

func (e *encoder) structure(t string, v any) error {
	fields, err := splitSignature(t[1 : len(t)-1])
	if err != nil {
		return err
	}
	values, ok := v.([]any)
	if !ok || len(values) != len(fields) {
		return mismatch(t, v)
	}
	if err := e.enter(); err != nil {
		return err
	}
	defer e.leave()
	e.align(8)
	for i, f := range fields {
		if err := e.value(f, values[i]); err != nil {
			return err
		}
	}
	return nil
}

func mismatch(t string, v any) error {
	return fmt.Errorf("dbus: can't encode %T as %q", v, t)
}

// asInt reads any Go integer as an int64 within [lo, hi].
func asInt(v any, lo, hi int64) (int64, error) {
	rv := reflect.ValueOf(v)
	var n int64
	switch rv.Kind() {
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		n = rv.Int()
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		u := rv.Uint()
		if u > math.MaxInt64 {
			return 0, fmt.Errorf("dbus: %d out of range", u)
		}
		n = int64(u)
	default:
		return 0, fmt.Errorf("dbus: %T is not an integer", v)
	}
	if n < lo || n > hi {
		return 0, fmt.Errorf("dbus: %d out of range", n)
	}
	return n, nil
}

// asUint reads any Go integer as a uint64 within [0, hi].
func asUint(v any, hi uint64) (uint64, error) {
	rv := reflect.ValueOf(v)
	var n uint64
	switch rv.Kind() {
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		i := rv.Int()
		if i < 0 {
			return 0, fmt.Errorf("dbus: %d out of range", i)
		}
		n = uint64(i)
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		n = rv.Uint()
	default:
		return 0, fmt.Errorf("dbus: %T is not an integer", v)
	}
	if n > hi {
		return 0, fmt.Errorf("dbus: %d out of range", n)
	}
	return n, nil
}
