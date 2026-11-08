package thumbnail

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"hash/crc32"
	"image"
	"image/png"
	"io"
	"os"
	"path/filepath"
	"runtime/debug"
	"strconv"

	// The formats it decodes
	_ "image/gif"
	_ "image/jpeg"

	_ "golang.org/x/image/bmp"
	_ "golang.org/x/image/webp"

	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/procprio"
	"golang.org/x/image/draw"
)

const pngSignature = "\x89PNG\r\n\x1a\n"

// exitUnreadable is the child's exit code for a file it can't make a
// thumbnail of (recorded as failed, not tried again until it changes)
const exitUnreadable = 3

// ErrUnreadable: the file isn't an image it can decode, or is too large
var ErrUnreadable = errors.New("thumbnail: not an image it can make a thumbnail of")

// RunChild is `axiom thumbnail`: every thread to nice 10 and the lowest
// best-effort disk priority, a memory limit, then the request on stdin.
// It returns ErrUnreadable for a file it can't decode.
func RunChild(ctx context.Context, stdin io.Reader) error {
	if err := procprio.Background(10); err != nil {
		return err
	}
	debug.SetMemoryLimit(512 << 20)
	var req Request
	if err := json.NewDecoder(stdin).Decode(&req); err != nil {
		return err
	}
	return Make(req)
}

// ExitCode is the child's exit code for RunChild's error.
func ExitCode(err error) int {
	switch {
	case err == nil:
		return 0
	case errors.Is(err, ErrUnreadable):
		return exitUnreadable
	}
	return 1
}

// Make decodes req.Src, scales it to fit req.Size (never up), and writes
// it to req.Dst with the spec's text chunks: atomically, 0600 in a 0700
// folder.
func Make(req Request) error {
	f, err := os.Open(req.Src)
	if err != nil {
		return err
	}
	defer f.Close()
	cfg, _, err := image.DecodeConfig(f)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrUnreadable, err)
	}
	if cfg.Width <= 0 || cfg.Height <= 0 || int64(cfg.Width)*int64(cfg.Height) > maxPixels {
		return fmt.Errorf("%w: %dx%d", ErrUnreadable, cfg.Width, cfg.Height)
	}
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return err
	}
	src, _, err := image.Decode(io.LimitReader(f, maxBytes))
	if err != nil {
		return fmt.Errorf("%w: %v", ErrUnreadable, err)
	}
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	if longest := max(w, h); longest > req.Size {
		w, h = max(1, w*req.Size/longest), max(1, h*req.Size/longest)
	}
	dst := image.NewNRGBA(image.Rect(0, 0, w, h))
	draw.ApproxBiLinear.Scale(dst, dst.Bounds(), src, b, draw.Src, nil)
	texts := chunks(req)
	texts = append(texts, [2]string{"Thumb::Image::Width", strconv.Itoa(b.Dx())}, [2]string{"Thumb::Image::Height", strconv.Itoa(b.Dy())})
	return write(req.Dst, dst, texts)
}

// WriteFail records that a thumbnail of req.Src can't be made: an empty
// image carrying its URI and time.
func WriteFail(path string, req Request) error {
	return write(path, image.NewNRGBA(image.Rect(0, 0, 1, 1)), chunks(req))
}

func chunks(req Request) [][2]string {
	return [][2]string{
		{"Thumb::URI", req.URI},
		{"Thumb::MTime", strconv.FormatInt(req.MTime, 10)},
		{"Thumb::Size", strconv.FormatInt(req.Bytes, 10)},
		{"Software", "axiom"},
	}
}

func write(path string, img image.Image, texts [][2]string) error {
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return err
	}
	data := withTexts(buf.Bytes(), texts)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	return fsx.WriteFile(path, data, 0o600)
}

// withTexts puts tEXt chunks after a PNG's IHDR.
func withTexts(png []byte, texts [][2]string) []byte {
	// The signature, then IHDR: 4 length, 4 type, 13 data, 4 CRC
	cut := 8 + 4 + 4 + 13 + 4
	out := append([]byte{}, png[:cut]...)
	for _, t := range texts {
		data := append(append([]byte(t[0]), 0), t[1]...)
		out = binary.BigEndian.AppendUint32(out, uint32(len(data)))
		start := len(out)
		out = append(out, "tEXt"...)
		out = append(out, data...)
		out = binary.BigEndian.AppendUint32(out, crc32.ChecksumIEEE(out[start:]))
	}
	return append(out, png[cut:]...)
}
