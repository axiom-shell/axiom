// Package thumbnail is the freedesktop thumbnail spec for the launcher's
// file rows: a file's thumbnail is $XDG_CACHE_HOME/thumbnails/{normal,
// large}/<md5 of its URI>.png, valid while its Thumb::URI and
// Thumb::MTime match the file, so a file manager's thumbnails (videos and
// PDFs among them) are reused and axiom's are shared back. axiom makes
// them only for images (png, jpeg, gif, webp, bmp), in a child process
// (`axiom thumbnail`, at nice 10 and the lowest best-effort disk
// priority: a 50 MP image decodes into ~200 MB that must not land in the
// daemon), at most two at once, one per file however often it's asked; a
// file that fails is recorded under fail/axiom-1/ and not tried again
// until it changes. Docs: docs/dev/features/file-search.md.
package thumbnail

import (
	"bytes"
	"context"
	"crypto/md5"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/filesearch"
)

// ChildCommand is the hidden subcommand that makes one thumbnail.
const ChildCommand = "thumbnail"

// Sizes: the spec's folders and their longest side
var sizes = map[string]int{"normal": 128, "large": 256}

// Limits on what is decoded: larger is refused (a decompression bomb)
const (
	maxPixels = 50_000_000
	maxBytes  = 64 << 20
	// An SVG this small is shown as itself
	maxSVG = 1 << 20
	// Made at once, and how long one may take
	maxRunning = 2
	timeout    = 30 * time.Second
)

// failDir is where this app's failures are recorded (the spec's
// fail/<app>-<version>/)
const failDir = "fail/axiom-1"

// The types axiom makes thumbnails of, by extension
var makes = map[string]bool{".png": true, ".jpg": true, ".jpeg": true, ".gif": true, ".webp": true, ".bmp": true}

// Options configure a Service.
type Options struct {
	// CacheHome is $XDG_CACHE_HOME (thumbnails/ is under it)
	CacheHome string
	// Exe is the binary run as the child (default /proc/self/exe)
	Exe string
	// Go runs a thumbnail's making, owned by the caller (the daemon's
	// tasks: its end kills the child); default a plain goroutine
	Go func(func(ctx context.Context))
}

// Service answers thumbnails.
type Service struct {
	o        Options
	sem      chan struct{}
	mu       sync.Mutex
	inflight map[string]*call
}

type call struct {
	done chan struct{}
	res  Result
	err  error
}

// New is a Service.
func New(o Options) *Service {
	if o.Exe == "" {
		o.Exe = "/proc/self/exe"
	}
	if o.Go == nil {
		o.Go = func(fn func(context.Context)) { go fn(context.Background()) }
	}
	return &Service{o: o, sem: make(chan struct{}, maxRunning), inflight: map[string]*call{}}
}

// Result is a file's thumbnail: Path the image to show ("" when there is
// none and none can be made), Failed when making one failed.
type Result struct {
	Path   string `json:"path"`
	Failed bool   `json:"failed"`
}

// Request is what the child is asked, as JSON on its stdin.
type Request struct {
	Src   string `json:"src"`
	Dst   string `json:"dst"`
	Size  int    `json:"size"` // the longest side
	URI   string `json:"uri"`
	MTime int64  `json:"mtime"` // seconds
	Bytes int64  `json:"bytes"`
}

// Hash is the md5 of a file URI, as the spec names thumbnails.
func Hash(uri string) string {
	sum := md5.Sum([]byte(uri))
	return hex.EncodeToString(sum[:])
}

// Get is the thumbnail of the file at path (absolute) at size ("normal"
// or "large"), made when it can be and isn't yet.
func (s *Service) Get(ctx context.Context, path, size string) (Result, error) {
	px, ok := sizes[size]
	if !ok {
		return Result{}, axerr.New(axerr.BadRequest, "a thumbnail is normal or large, not %q", size)
	}
	if !filepath.IsAbs(path) {
		return Result{}, axerr.New(axerr.BadRequest, "a thumbnail of an absolute path")
	}
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() {
		return Result{}, nil
	}
	ext := strings.ToLower(filepath.Ext(path))
	if ext == ".svg" && info.Size() < maxSVG {
		return Result{Path: path}, nil
	}
	uri := filesearch.FileURI(path)
	name := Hash(uri) + ".png"
	thumb := filepath.Join(s.o.CacheHome, "thumbnails", size, name)
	mtime := info.ModTime().Unix()
	if Valid(thumb, uri, mtime) {
		return Result{Path: thumb}, nil
	}
	fail := filepath.Join(s.o.CacheHome, "thumbnails", failDir, name)
	if Valid(fail, uri, mtime) {
		return Result{Failed: true}, nil
	}
	if !makes[ext] {
		return Result{}, nil
	}
	req := Request{Src: path, Dst: thumb, Size: px, URI: uri, MTime: mtime, Bytes: info.Size()}
	if info.Size() > maxBytes {
		WriteFail(fail, req)
		return Result{Failed: true}, nil
	}
	return s.make(ctx, req, fail)
}

// make runs the child for req, once however many ask.
func (s *Service) make(ctx context.Context, req Request, fail string) (Result, error) {
	s.mu.Lock()
	c, ok := s.inflight[req.Dst]
	if !ok {
		c = &call{done: make(chan struct{})}
		s.inflight[req.Dst] = c
		s.mu.Unlock()
		// Made for whoever asks: a caller giving up doesn't stop it
		s.o.Go(func(ctx context.Context) { s.run(ctx, c, req, fail) })
	} else {
		s.mu.Unlock()
	}
	select {
	case <-c.done:
		return c.res, c.err
	case <-ctx.Done():
		return Result{}, ctx.Err()
	}
}

func (s *Service) run(ctx context.Context, c *call, req Request, fail string) {
	defer func() {
		s.mu.Lock()
		delete(s.inflight, req.Dst)
		s.mu.Unlock()
		close(c.done)
	}()
	s.sem <- struct{}{}
	defer func() { <-s.sem }()
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	data, _ := json.Marshal(req)
	cmd := exec.CommandContext(ctx, s.o.Exe, ChildCommand)
	cmd.Env = []string{"GOMAXPROCS=2"}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Stdin = bytes.NewReader(data)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		if ctx.Err() == nil && cmd.ProcessState != nil && cmd.ProcessState.ExitCode() == exitUnreadable {
			WriteFail(fail, req)
			c.res = Result{Failed: true}
			return
		}
		// Failed, not Unavailable: the daemon answered, and the shell
		// doesn't ask again (it asks again what a lost connection cut off)
		c.err = axerr.Wrap(axerr.Failed, err, "making the thumbnail failed")
		return
	}
	c.res = Result{Path: req.Dst}
}

// Valid says whether the PNG at file is a thumbnail of uri at mtime (its
// Thumb::URI and Thumb::MTime).
func Valid(file, uri string, mtime int64) bool {
	f, err := os.Open(file)
	if err != nil {
		return false
	}
	defer f.Close()
	head := make([]byte, 64<<10)
	n, _ := f.Read(head)
	text := Texts(head[:n])
	return text["Thumb::URI"] == uri && text["Thumb::MTime"] == strconv.FormatInt(mtime, 10)
}

// Texts are a PNG's tEXt chunks before its image data.
func Texts(png []byte) map[string]string {
	out := map[string]string{}
	if len(png) < 8 || string(png[:8]) != pngSignature {
		return out
	}
	for b := png[8:]; len(b) >= 12; {
		n := int(binary.BigEndian.Uint32(b))
		typ := string(b[4:8])
		if n < 0 || len(b) < 12+n || typ == "IDAT" {
			break
		}
		if typ == "tEXt" {
			if k, v, ok := bytes.Cut(b[8:8+n], []byte{0}); ok {
				out[string(k)] = string(v)
			}
		}
		b = b[12+n:]
	}
	return out
}
