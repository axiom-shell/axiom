package fileindex

import (
	"bufio"
	"encoding/binary"
	"errors"
	"io"
)

// The crawl child's messages on its stdout: a uvarint length, then a
// kind byte and its payload. Binary, so the daemon reads a folder's
// names straight from the frame, allocating nothing per entry.
const (
	msgDir        = 'D' // a folder read: its path, time and entries
	msgGone       = 'G' // stat: a folder is gone (or no folder now)
	msgUnreadable = 'U' // one more folder couldn't be read
	msgTruncated  = 'T' // the cap was reached: the rest was left out
	msgEnd        = 'E' // done
	// The walker is still going: sent by the walking goroutine itself at
	// most every progressEvery, so a child blocked in the kernel sends none
	msgProgress = 'P'
)

// Kinds of an entry in a msgDir
const (
	kindFile = 0
	kindDir  = 1
	kindLink = 2
)

// maxFrame bounds a frame the daemon reads (a folder of ~100k long names)
const maxFrame = 64 << 20

// frameWriter writes the child's frames.
type frameWriter struct {
	w   *bufio.Writer
	buf []byte
}

func (f *frameWriter) begin(kind byte) { f.buf = append(f.buf[:0], kind) }
func (f *frameWriter) bytes(b []byte) {
	f.buf = binary.AppendUvarint(f.buf, uint64(len(b)))
	f.buf = append(f.buf, b...)
}
func (f *frameWriter) str(s string) {
	f.buf = binary.AppendUvarint(f.buf, uint64(len(s)))
	f.buf = append(f.buf, s...)
}
func (f *frameWriter) uvarint(v uint64) { f.buf = binary.AppendUvarint(f.buf, v) }
func (f *frameWriter) varint(v int64)   { f.buf = binary.AppendVarint(f.buf, v) }

func (f *frameWriter) end() error {
	var n [binary.MaxVarintLen64]byte
	if _, err := f.w.Write(n[:binary.PutUvarint(n[:], uint64(len(f.buf)))]); err != nil {
		return err
	}
	_, err := f.w.Write(f.buf)
	return err
}

// frameReader reads them; a frame's bytes are valid until the next read.
type frameReader struct {
	r   *bufio.Reader
	buf []byte
}

var errFrame = errors.New("fileindex: a malformed message from the crawl")

func (f *frameReader) next() (kind byte, payload []byte, err error) {
	n, err := binary.ReadUvarint(f.r)
	if err != nil {
		return 0, nil, err
	}
	if n == 0 || n > maxFrame {
		return 0, nil, errFrame
	}
	if cap(f.buf) < int(n) {
		f.buf = make([]byte, n)
	}
	f.buf = f.buf[:n]
	if _, err := io.ReadFull(f.r, f.buf); err != nil {
		return 0, nil, errFrame
	}
	return f.buf[0], f.buf[1:], nil
}

// cursor reads a payload's fields.
type cursor struct {
	b   []byte
	bad bool
}

func (c *cursor) uvarint() uint64 {
	v, n := binary.Uvarint(c.b)
	if n <= 0 {
		c.bad = true
		return 0
	}
	c.b = c.b[n:]
	return v
}

func (c *cursor) varint() int64 {
	v, n := binary.Varint(c.b)
	if n <= 0 {
		c.bad = true
		return 0
	}
	c.b = c.b[n:]
	return v
}

func (c *cursor) bytes() []byte {
	n := c.uvarint()
	if c.bad || n > uint64(len(c.b)) {
		c.bad = true
		return nil
	}
	out := c.b[:n]
	c.b = c.b[n:]
	return out
}

func (c *cursor) byte() byte {
	if len(c.b) == 0 {
		c.bad = true
		return 0
	}
	v := c.b[0]
	c.b = c.b[1:]
	return v
}
