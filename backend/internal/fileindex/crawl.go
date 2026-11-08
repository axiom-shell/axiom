package fileindex

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"runtime"
	"runtime/debug"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/procprio"
	"golang.org/x/sys/unix"
)

// ChildCommand is the hidden subcommand the daemon runs as the crawl
// child (`axiom index-crawl`).
const ChildCommand = "index-crawl"

// CrawlRequest is what the crawl child is asked, as one JSON value on its
// stdin (never in argv, where any process could read the paths).
type CrawlRequest struct {
	Roots    []string `json:"roots"`
	Excludes []string `json:"excludes"`
	// Skip are folders always left out ($XDG_RUNTIME_DIR, the
	// thumbnails' cache), besides /proc, /sys, /dev and /run
	Skip   []string `json:"skip"`
	Hidden bool     `json:"hidden"`
	// Start are folders to walk whole, breadth first (a crawl)
	Start []string `json:"start,omitempty"`
	// Stat are folders to check: each whose time changed is read again,
	// each gone said so (the stat pass)
	Stat []StatDir `json:"stat,omitempty"`
	// Max is how many entries a crawl sends at most (0: no cap). A stat
	// pass has none: the folders it reads again are the index's already,
	// whose own cap leaves out what they add
	Max int `json:"max"`
	// Pause is a sleep every 128 folders read (and every 1024 checked),
	// in ms: a crawl paces itself even where the disk ignores its idle
	// priority
	Pause int `json:"pause"`
}

// StatDir is one folder the stat pass checks: its path and the time the
// index has for it.
type StatDir struct {
	Path  string `json:"path"`
	Mtime int64  `json:"mtime"`
}

// RunChild is `axiom index-crawl`: before anything else every thread goes
// to SCHED_IDLE and the idle I/O class (threads made later inherit both),
// with one P and a small heap; then it serves the request on stdin. It
// never crawls at normal priority: failing to lower itself fails.
func RunChild(ctx context.Context, stdin io.Reader, stdout io.Writer) error {
	if err := procprio.Idle(); err != nil {
		return err
	}
	runtime.GOMAXPROCS(1)
	debug.SetGCPercent(20)
	return Serve(ctx, stdin, stdout)
}

// Serve reads one CrawlRequest and answers it in frames (wire.go).
func Serve(ctx context.Context, stdin io.Reader, stdout io.Writer) error {
	var req CrawlRequest
	if err := json.NewDecoder(stdin).Decode(&req); err != nil {
		return err
	}
	f := newFilter(cleanRoots(req.Roots), req.Excludes, req.Skip, req.Hidden)
	w := &frameWriter{w: bufio.NewWriterSize(stdout, 64<<10)}
	pause := time.Duration(req.Pause) * time.Millisecond
	c := &crawler{f: f, w: w, pause: pause}
	var err error
	if len(req.Stat) > 0 {
		err = c.stat(ctx, req.Stat)
	} else {
		c.max = req.Max
		err = c.crawl(ctx, req.Start)
	}
	if err == errCapped {
		w.begin(msgTruncated)
		err = w.end()
	}
	if err != nil {
		return err
	}
	w.begin(msgEnd)
	if err := w.end(); err != nil {
		return err
	}
	return w.w.Flush()
}

type crawler struct {
	f     *filter
	w     *frameWriter
	max   int
	sent  int
	pause time.Duration
	read  int
}

// errCapped: the cap was reached
var errCapped = errors.New("fileindex: the cap")

// send writes one folder; errCapped once the cap is reached.
func (c *crawler) send(path string, fo folder) error {
	c.w.begin(msgDir)
	c.w.str(path)
	c.w.varint(fo.mtime)
	c.w.uvarint(uint64(len(fo.kids)))
	for _, k := range fo.kids {
		c.w.bytes(k.Name)
		kind := byte(kindFile)
		if k.Dir {
			kind = kindDir
		} else if k.Link {
			kind = kindLink
		}
		c.w.buf = append(c.w.buf, kind)
		c.w.varint(k.Mtime)
	}
	if err := c.w.end(); err != nil {
		return err
	}
	c.sent += len(fo.kids)
	if c.max > 0 && c.sent >= c.max {
		return errCapped
	}
	return nil
}

func (c *crawler) simple(kind byte, path string) error {
	c.w.begin(kind)
	if path != "" {
		c.w.str(path)
	}
	return c.w.end()
}

// paced sleeps every n steps, sending what it has first.
func (c *crawler) paced(ctx context.Context, every int) error {
	c.read++
	if c.pause <= 0 || c.read%every != 0 {
		return ctx.Err()
	}
	if err := c.w.w.Flush(); err != nil {
		return err
	}
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(c.pause):
		return nil
	}
}

func (c *crawler) crawl(ctx context.Context, start []string) error {
	for _, s := range start {
		root := c.f.rootOf(s)
		if root == "" {
			continue
		}
		queue := []string{s}
		for len(queue) > 0 {
			d := queue[0]
			queue = queue[1:]
			fo, err := c.f.read(root, d)
			if err != nil {
				kind, path := byte(msgUnreadable), ""
				if d == s && d != root {
					// A start folder gone: its parent is read again
					kind, path = msgGone, d
				}
				if err := c.simple(kind, path); err != nil {
					return err
				}
				continue
			}
			if err := c.send(d, fo); err != nil {
				return err
			}
			for _, k := range fo.kids {
				if k.Dir {
					queue = append(queue, join(d, string(k.Name)))
				}
			}
			if err := c.paced(ctx, 128); err != nil {
				return err
			}
		}
	}
	return nil
}

func (c *crawler) stat(ctx context.Context, dirs []StatDir) error {
	for _, sd := range dirs {
		root := c.f.rootOf(sd.Path)
		var st unix.Stat_t
		statFn := unix.Lstat
		if sd.Path == root {
			statFn = unix.Stat
		}
		if root == "" || statFn(sd.Path, &st) != nil || st.Mode&unix.S_IFMT != unix.S_IFDIR {
			if err := c.simple(msgGone, sd.Path); err != nil {
				return err
			}
		} else if statTime(&st) != sd.Mtime {
			fo, err := c.f.read(root, sd.Path)
			if err != nil {
				err = c.simple(msgGone, sd.Path)
			} else {
				err = c.send(sd.Path, fo)
			}
			if err != nil {
				return err
			}
		}
		if err := c.paced(ctx, 1024); err != nil {
			return err
		}
	}
	return nil
}
