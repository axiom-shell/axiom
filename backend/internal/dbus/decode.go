package dbus

import (
	"encoding/binary"
	"errors"
	"fmt"
	"math"
	"unicode/utf8"
)

// What each type decodes to:
//
//	y uint8, b bool, n int16, q uint16, i int32, u uint32, x int64,
//	t uint64, d float64, s string, o ObjectPath, g Signature, h UnixFD,
//	v Variant, (…) []any
//	ay []byte, as []string, ao []ObjectPath, a{sv} map[string]Variant,
//	a{…} map[any]any, any other array []any
type decoder struct {
	b     []byte
	off   int
	order binary.ByteOrder
	fds   uint32 // descriptors the message carries: an h indexes them
	depth int
}

var errShort = errors.New("dbus: a message ends early")

// Unmarshal decodes a little-endian body by sig (for tests and fakes).
func Unmarshal(sig string, b []byte, fds uint32) ([]any, error) {
	d := &decoder{b: b, order: binary.LittleEndian, fds: fds}
	return d.values(sig)
}

func (d *decoder) values(sig string) ([]any, error) {
	types, err := splitSignature(sig)
	if err != nil {
		return nil, err
	}
	out := make([]any, 0, len(types))
	for _, t := range types {
		v, err := d.value(t)
		if err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, nil
}

func (d *decoder) align(n int) error {
	next := (d.off + n - 1) &^ (n - 1)
	if next > len(d.b) {
		return errShort
	}
	for _, c := range d.b[d.off:next] {
		if c != 0 {
			return fmt.Errorf("dbus: padding isn't zero")
		}
	}
	d.off = next
	return nil
}

func (d *decoder) take(n int) ([]byte, error) {
	if n < 0 || d.off+n > len(d.b) {
		return nil, errShort
	}
	b := d.b[d.off : d.off+n]
	d.off += n
	return b, nil
}

func (d *decoder) u8() (uint8, error) {
	b, err := d.take(1)
	if err != nil {
		return 0, err
	}
	return b[0], nil
}

func (d *decoder) u16() (uint16, error) {
	if err := d.align(2); err != nil {
		return 0, err
	}
	b, err := d.take(2)
	if err != nil {
		return 0, err
	}
	return d.order.Uint16(b), nil
}

func (d *decoder) u32() (uint32, error) {
	if err := d.align(4); err != nil {
		return 0, err
	}
	b, err := d.take(4)
	if err != nil {
		return 0, err
	}
	return d.order.Uint32(b), nil
}

func (d *decoder) u64() (uint64, error) {
	if err := d.align(8); err != nil {
		return 0, err
	}
	b, err := d.take(8)
	if err != nil {
		return 0, err
	}
	return d.order.Uint64(b), nil
}

func (d *decoder) str() (string, error) {
	n, err := d.u32()
	if err != nil {
		return "", err
	}
	if n > maxMessage {
		return "", errShort
	}
	b, err := d.take(int(n) + 1)
	if err != nil {
		return "", err
	}
	if b[n] != 0 {
		return "", fmt.Errorf("dbus: a string isn't NUL-terminated")
	}
	s := string(b[:n])
	if !utf8.ValidString(s) {
		return "", fmt.Errorf("dbus: a string isn't UTF-8")
	}
	return s, nil
}

func (d *decoder) sig() (string, error) {
	n, err := d.u8()
	if err != nil {
		return "", err
	}
	b, err := d.take(int(n) + 1)
	if err != nil {
		return "", err
	}
	if b[n] != 0 {
		return "", fmt.Errorf("dbus: a signature isn't NUL-terminated")
	}
	s := string(b[:n])
	if _, err := splitSignature(s); err != nil {
		return "", err
	}
	return s, nil
}

func (d *decoder) value(t string) (any, error) {
	switch t[0] {
	case 'y':
		return d.u8()
	case 'b':
		n, err := d.u32()
		if err == nil && n > 1 {
			err = fmt.Errorf("dbus: a boolean of %d", n)
		}
		return n == 1, err
	case 'n':
		n, err := d.u16()
		return int16(n), err
	case 'q':
		return d.u16()
	case 'i':
		n, err := d.u32()
		return int32(n), err
	case 'u':
		return d.u32()
	case 'x':
		n, err := d.u64()
		return int64(n), err
	case 't':
		return d.u64()
	case 'd':
		n, err := d.u64()
		return math.Float64frombits(n), err
	case 's':
		return d.str()
	case 'o':
		s, err := d.str()
		if err == nil && !validPath(s) {
			err = fmt.Errorf("dbus: %q is not an object path", s)
		}
		return ObjectPath(s), err
	case 'g':
		s, err := d.sig()
		return Signature(s), err
	case 'h':
		n, err := d.u32()
		if err == nil && n >= d.fds {
			err = fmt.Errorf("dbus: descriptor %d of %d", n, d.fds)
		}
		return UnixFD(n), err
	case 'v':
		if err := d.enter(); err != nil {
			return nil, err
		}
		defer d.leave()
		s, err := d.sig()
		if err != nil {
			return nil, err
		}
		if err := singleType(s); err != nil {
			return nil, err
		}
		v, err := d.value(s)
		return Variant{Sig: Signature(s), Value: v}, err
	case 'a':
		return d.array(t[1:])
	case '(':
		return d.structure(t)
	}
	return nil, fmt.Errorf("dbus: can't decode %q", t)
}

func (d *decoder) enter() error {
	if d.depth++; d.depth > maxDepth {
		return fmt.Errorf("dbus: a value nested deeper than %d", maxDepth)
	}
	return nil
}

func (d *decoder) leave() { d.depth-- }

func (d *decoder) array(elem string) (any, error) {
	if err := d.enter(); err != nil {
		return nil, err
	}
	defer d.leave()
	n, err := d.u32()
	if err != nil {
		return nil, err
	}
	if n > maxArrayBytes {
		return nil, fmt.Errorf("dbus: an array of %d bytes", n)
	}
	if err := d.align(alignOf(elem[0])); err != nil {
		return nil, err
	}
	end := d.off + int(n)
	if end > len(d.b) {
		return nil, errShort
	}
	each := func(fn func() error) error {
		for d.off < end {
			if err := fn(); err != nil {
				return err
			}
		}
		if d.off != end {
			return fmt.Errorf("dbus: an array's elements overrun its length")
		}
		return nil
	}
	switch {
	case elem == "y":
		b, _ := d.take(int(n))
		return append(make([]byte, 0, n), b...), nil
	case elem == "s":
		var out []string
		return out, each(func() error { s, err := d.str(); out = append(out, s); return err })
	case elem == "o":
		var out []ObjectPath
		return out, each(func() error {
			v, err := d.value("o")
			if err == nil {
				out = append(out, v.(ObjectPath))
			}
			return err
		})
	case elem == "{sv}":
		out := map[string]Variant{}
		return out, each(func() error {
			if err := d.align(8); err != nil {
				return err
			}
			k, err := d.str()
			if err != nil {
				return err
			}
			v, err := d.value("v")
			if err == nil {
				out[k] = v.(Variant)
			}
			return err
		})
	case elem[0] == '{':
		key, val := elem[1:2], elem[2:len(elem)-1]
		out := map[any]any{}
		return out, each(func() error {
			if err := d.align(8); err != nil {
				return err
			}
			k, err := d.value(key)
			if err != nil {
				return err
			}
			v, err := d.value(val)
			out[k] = v
			return err
		})
	}
	var out []any
	return out, each(func() error { v, err := d.value(elem); out = append(out, v); return err })
}

func (d *decoder) structure(t string) (any, error) {
	if err := d.enter(); err != nil {
		return nil, err
	}
	defer d.leave()
	if err := d.align(8); err != nil {
		return nil, err
	}
	return d.values(t[1 : len(t)-1])
}
