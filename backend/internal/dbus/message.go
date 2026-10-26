package dbus

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"io"
	"os"
)

// MessageType is what a message is.
type MessageType uint8

// The message types
const (
	TypeMethodCall   MessageType = 1
	TypeMethodReturn MessageType = 2
	TypeError        MessageType = 3
	TypeSignal       MessageType = 4
)

// Message flags
const (
	FlagNoReplyExpected byte = 0x1
	FlagNoAutoStart     byte = 0x2
)

// Header field codes
const (
	fieldPath        = 1
	fieldInterface   = 2
	fieldMember      = 3
	fieldErrorName   = 4
	fieldReplySerial = 5
	fieldDestination = 6
	fieldSender      = 7
	fieldSignature   = 8
	fieldUnixFDs     = 9
)

// Message is one D-Bus message, its body decoded.
type Message struct {
	Type        MessageType
	Flags       byte
	Serial      uint32
	Path        ObjectPath
	Interface   string
	Member      string
	ErrorName   string
	ReplySerial uint32
	Destination string
	Sender      string
	Signature   Signature
	Body        []any

	// Files are the descriptors that came with it, which its UnixFD
	// values index. Whoever receives a message with descriptors takes
	// the ones it keeps (File) and closes the rest (Close).
	Files []*os.File
}

// File takes the descriptor fd names: the caller owns it.
func (m *Message) File(fd UnixFD) (*os.File, error) {
	if fd < 0 || int(fd) >= len(m.Files) || m.Files[fd] == nil {
		return nil, fmt.Errorf("dbus: no descriptor %d in the message", fd)
	}
	f := m.Files[fd]
	m.Files[fd] = nil
	return f, nil
}

// Close closes the descriptors nobody took.
func (m *Message) Close() {
	for i, f := range m.Files {
		if f != nil {
			f.Close()
			m.Files[i] = nil
		}
	}
}

// Store copies the body's values into ptrs, in order: each ptr is a
// pointer to the type its value decodes to (see decode.go), or *any.
func (m *Message) Store(ptrs ...any) error {
	return Store(m.Body, ptrs...)
}

// Store copies values into ptrs (see Message.Store).
func Store(values []any, ptrs ...any) error {
	if len(ptrs) > len(values) {
		return fmt.Errorf("dbus: %d values, %d wanted", len(values), len(ptrs))
	}
	for i, p := range ptrs {
		if err := store(values[i], p); err != nil {
			return fmt.Errorf("dbus: value %d: %w", i, err)
		}
	}
	return nil
}

func store(v any, p any) error {
	switch p := p.(type) {
	case *any:
		*p = v
		return nil
	case *Variant:
		if x, ok := v.(Variant); ok {
			*p = x
			return nil
		}
	case *string:
		switch x := v.(type) {
		case string:
			*p = x
			return nil
		case ObjectPath:
			*p = string(x)
			return nil
		case Signature:
			*p = string(x)
			return nil
		}
	case *ObjectPath:
		if x, ok := v.(ObjectPath); ok {
			*p = x
			return nil
		}
	case *bool:
		if x, ok := v.(bool); ok {
			*p = x
			return nil
		}
	case *uint8:
		if x, ok := v.(uint8); ok {
			*p = x
			return nil
		}
	case *uint32:
		if x, ok := v.(uint32); ok {
			*p = x
			return nil
		}
	case *int32:
		if x, ok := v.(int32); ok {
			*p = x
			return nil
		}
	case *uint64:
		if x, ok := v.(uint64); ok {
			*p = x
			return nil
		}
	case *int64:
		if x, ok := v.(int64); ok {
			*p = x
			return nil
		}
	case *float64:
		if x, ok := v.(float64); ok {
			*p = x
			return nil
		}
	case *UnixFD:
		if x, ok := v.(UnixFD); ok {
			*p = x
			return nil
		}
	case *[]string:
		if x, ok := v.([]string); ok {
			*p = x
			return nil
		}
	case *[]byte:
		if x, ok := v.([]byte); ok {
			*p = x
			return nil
		}
	case *[]ObjectPath:
		if x, ok := v.([]ObjectPath); ok {
			*p = x
			return nil
		}
	case *map[string]Variant:
		if x, ok := v.(map[string]Variant); ok {
			*p = x
			return nil
		}
	case *[]any:
		if x, ok := v.([]any); ok {
			*p = x
			return nil
		}
	}
	return fmt.Errorf("%T can't be stored in %T", v, p)
}

// Marshal encodes the message with its serial: the bytes and the
// descriptors to send with them (its UnixFD values are descriptor
// numbers here, not indexes).
func (m *Message) Marshal(serial uint32) ([]byte, []int, error) {
	body, fds, err := Marshal(string(m.Signature), m.Body...)
	if err != nil {
		return nil, nil, err
	}
	var fields []any
	add := func(code byte, sig Signature, v any) {
		fields = append(fields, []any{code, Variant{Sig: sig, Value: v}})
	}
	if m.Path != "" {
		add(fieldPath, "o", m.Path)
	}
	if m.Interface != "" {
		add(fieldInterface, "s", m.Interface)
	}
	if m.Member != "" {
		add(fieldMember, "s", m.Member)
	}
	if m.ErrorName != "" {
		add(fieldErrorName, "s", m.ErrorName)
	}
	if m.ReplySerial != 0 {
		add(fieldReplySerial, "u", m.ReplySerial)
	}
	if m.Destination != "" {
		add(fieldDestination, "s", m.Destination)
	}
	if m.Sender != "" {
		add(fieldSender, "s", m.Sender)
	}
	if m.Signature != "" {
		add(fieldSignature, "g", m.Signature)
	}
	if len(fds) > 0 {
		add(fieldUnixFDs, "u", uint32(len(fds)))
	}
	e := &encoder{}
	e.u8('l')
	e.u8(uint8(m.Type))
	e.u8(m.Flags)
	e.u8(1) // protocol version
	e.u32(uint32(len(body)))
	e.u32(serial)
	if err := e.value("a(yv)", fields); err != nil {
		return nil, nil, err
	}
	e.align(8)
	if len(e.b)+len(body) > maxMessage {
		return nil, nil, fmt.Errorf("dbus: a message of more than %d bytes", maxMessage)
	}
	return append(e.b, body...), fds, nil
}

// ReadMessage reads one message; takeFD gives the descriptors it says
// came with it.
func ReadMessage(r *bufio.Reader, takeFD func() (*os.File, error)) (*Message, error) {
	head := make([]byte, 16)
	if _, err := io.ReadFull(r, head); err != nil {
		return nil, err
	}
	var order binary.ByteOrder
	switch head[0] {
	case 'l':
		order = binary.LittleEndian
	case 'B':
		order = binary.BigEndian
	default:
		return nil, fmt.Errorf("dbus: unknown byte order %q", head[0])
	}
	if head[3] != 1 {
		return nil, fmt.Errorf("dbus: protocol version %d", head[3])
	}
	bodyLen := order.Uint32(head[4:])
	fieldsLen := order.Uint32(head[12:])
	headerLen := (16 + int(fieldsLen) + 7) &^ 7
	if fieldsLen > maxArrayBytes || uint64(headerLen)+uint64(bodyLen) > maxMessage {
		return nil, fmt.Errorf("dbus: a message of more than %d bytes", maxMessage)
	}
	buf := make([]byte, headerLen+int(bodyLen))
	copy(buf, head)
	if _, err := io.ReadFull(r, buf[16:]); err != nil {
		return nil, err
	}
	m := &Message{Type: MessageType(head[1]), Flags: head[2], Serial: order.Uint32(head[8:])}
	d := &decoder{b: buf[:headerLen], off: 12, order: order}
	raw, err := d.value("a(yv)")
	if err != nil {
		return nil, fmt.Errorf("dbus: the header: %w", err)
	}
	var fds uint32
	for _, f := range raw.([]any) {
		f := f.([]any)
		code, v := f[0].(uint8), f[1].(Variant).Value
		var ok bool
		switch code {
		case fieldPath:
			m.Path, ok = v.(ObjectPath)
		case fieldInterface:
			m.Interface, ok = v.(string)
		case fieldMember:
			m.Member, ok = v.(string)
		case fieldErrorName:
			m.ErrorName, ok = v.(string)
		case fieldReplySerial:
			m.ReplySerial, ok = v.(uint32)
		case fieldDestination:
			m.Destination, ok = v.(string)
		case fieldSender:
			m.Sender, ok = v.(string)
		case fieldSignature:
			m.Signature, ok = v.(Signature)
		case fieldUnixFDs:
			fds, ok = v.(uint32)
		default:
			ok = true // unknown fields are ignored
		}
		if !ok {
			return nil, fmt.Errorf("dbus: header field %d has the wrong type", code)
		}
	}
	for i := uint32(0); i < fds; i++ {
		f, err := takeFD()
		if err != nil {
			m.Close()
			return nil, fmt.Errorf("dbus: the message names %d descriptors: %w", fds, err)
		}
		m.Files = append(m.Files, f)
	}
	body := &decoder{b: buf[headerLen:], order: order, fds: fds}
	if m.Body, err = body.values(string(m.Signature)); err != nil {
		m.Close()
		return nil, err
	}
	if body.off != len(body.b) {
		m.Close()
		return nil, fmt.Errorf("dbus: the body is longer than its signature")
	}
	return m, nil
}
