// Package clipboard is the clipboard history the launcher searches (":"),
// in place of wl-paste --watch and cliphist: every selection recorded as
// it comes (text, and images with their size and dimensions), newest
// first, deduplicated and capped, and copied back from memory. Nothing is
// written to disk: an image is kept as a file in the runtime directory
// (tmpfs) for the shell to show, within a byte budget. Clips a password
// manager marks secret are never recorded. Docs:
// docs/dev/features/launcher-providers.md.
package clipboard

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"image"
	_ "image/gif" // dimensions of the formats the standard library reads
	_ "image/jpeg"
	_ "image/png"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/xdg"
)

// Limits on what's recorded and kept
const (
	MaxText       = 100000   // characters: longer clips aren't recorded
	MaxImage      = 32 << 20 // bytes in one image
	MaxFile       = 64 << 20 // bytes copied from a file, or saved from the clipboard
	ImageBudget   = 256 << 20
	PreviewLength = 1000 // characters of a text pushed to the shell
	readTimeout   = 2 * time.Second
)

// The types a clip is read as, in the order preferred
var (
	textMimes  = []string{"text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "STRING", "TEXT"}
	imageMimes = []string{"image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp"}
	// What a password manager marks a secret clip with (KeePassXC, …);
	// wl-paste's CLIPBOARD_STATE=sensitive is the same
	secretMime = "x-kde-passwordManagerHint"
	// HTML that is just an image, as a browser copies one: its src
	imgOnly = regexp.MustCompile(`(?is)^\s*(?:<meta[^>]*>)?\s*<img\b[^>]*\bsrc="([^"]*)"[^>]*>\s*$`)
)

// Offer is a selection to record (datacontrol.Offer).
type Offer interface {
	Mimes() []string
	Receive(ctx context.Context, mime string, max int, timeout time.Duration) ([]byte, error)
}

// Options configure the history.
type Options struct {
	// Dir holds the images' files ($XDG_RUNTIME_DIR/axiom/clipboard),
	// emptied at the start
	Dir string
	// Set makes the daemon the clipboard's source (datacontrol.Device.Set)
	Set func(mimes []string, data map[string][]byte) error
	// Current is the selection now (nil: none)
	Current func() Offer
	// OnChange is told when the entries change
	OnChange func()
	Log      *slog.Logger
}

// Entry is one clip, as the shell shows it.
type Entry struct {
	ID string `json:"id"`
	// Text is the clip (its first PreviewLength characters; Text gives
	// it whole), or an image HTML's markup
	Text string `json:"text"`
	Time int64  `json:"time"` // ms since the epoch
	// An image's: its format (png, jpeg, …), "1920x1080" when known, its
	// size ("1.2 MiB") and file
	Format     string `json:"format,omitempty"`
	Dimensions string `json:"dimensions,omitempty"`
	Size       string `json:"size,omitempty"`
	Image      string `json:"image,omitempty"`
	// HTML that is just an image (a browser's copy): Image is its src
	HTML bool `json:"html,omitempty"`
}

type entry struct {
	Entry
	text  string // the whole text (or HTML)
	mime  string // an image's type
	hash  [32]byte
	bytes int // an image file's size
}

// History is the clipboard history.
type History struct {
	o Options

	queue chan Offer

	mu      sync.Mutex
	enabled bool
	max     int
	next    int
	entries []*entry // newest first
}

// New returns an empty history, recording nothing until Configure turns
// it on.
func New(o Options) *History {
	if o.Log == nil {
		o.Log = slog.New(slog.DiscardHandler)
	}
	return &History{o: o, queue: make(chan Offer, 8), max: 100}
}

// Configure turns recording on or off (off forgets everything) and caps
// the history at max.
func (h *History) Configure(enabled bool, max int) {
	h.mu.Lock()
	changed := h.enabled != enabled || h.max != max
	h.enabled, h.max = enabled, max
	if !enabled {
		h.entries = nil
		h.removeFiles()
	}
	h.trim()
	h.mu.Unlock()
	if changed {
		h.changed()
	}
}

// Selected queues a new selection to record (datacontrol's OnSelection:
// it never blocks).
func (h *History) Selected(o Offer) {
	if o == nil {
		return
	}
	select {
	case h.queue <- o:
	default:
		h.o.Log.Warn("clipboard: too many clips at once: one wasn't recorded")
	}
}

// Run records the selections queued, in order, until ctx ends; then it
// removes the images' files.
func (h *History) Run(ctx context.Context) error {
	h.mu.Lock()
	h.removeFiles()
	h.mu.Unlock()
	defer func() {
		h.mu.Lock()
		h.removeFiles()
		h.mu.Unlock()
	}()
	for {
		select {
		case <-ctx.Done():
			return nil
		case o := <-h.queue:
			h.record(ctx, o)
		}
	}
}

// Entries are the clips, newest first, their texts cut to PreviewLength.
func (h *History) Entries() []Entry {
	h.mu.Lock()
	defer h.mu.Unlock()
	out := make([]Entry, 0, len(h.entries))
	for _, e := range h.entries {
		out = append(out, e.Entry)
	}
	return out
}

// Text is a clip's whole text.
func (h *History) Text(id string) (string, error) {
	h.mu.Lock()
	defer h.mu.Unlock()
	e := h.find(id)
	if e == nil {
		return "", axerr.New(axerr.NotFound, "no clip %s", id)
	}
	return e.text, nil
}

// Remove forgets a clip.
func (h *History) Remove(id string) {
	h.mu.Lock()
	i := slices.IndexFunc(h.entries, func(e *entry) bool { return e.ID == id })
	if i >= 0 {
		h.dropFile(h.entries[i])
		h.entries = slices.Delete(h.entries, i, i+1)
	}
	h.mu.Unlock()
	if i >= 0 {
		h.changed()
	}
}

// Clear forgets every clip.
func (h *History) Clear() {
	h.mu.Lock()
	h.entries = nil
	h.removeFiles()
	h.mu.Unlock()
	h.changed()
}

// Copy puts a clip back on the clipboard.
func (h *History) Copy(id string) error {
	h.mu.Lock()
	e := h.find(id)
	var mimes []string
	var data []byte
	var err error
	switch {
	case e == nil:
		err = axerr.New(axerr.NotFound, "no clip %s", id)
	case e.Format != "":
		mimes = []string{e.mime}
		data, err = os.ReadFile(e.Image)
	case e.HTML:
		mimes, data = []string{"text/html"}, []byte(e.text)
	default:
		mimes, data = textMimes, []byte(e.text)
	}
	h.mu.Unlock()
	if err != nil {
		return err
	}
	return h.set(mimes, data)
}

// CopyText puts text on the clipboard.
func (h *History) CopyText(text string) error { return h.set(textMimes, []byte(text)) }

// CopyFile puts a file's contents on the clipboard as mime (a
// screenshot).
func (h *History) CopyFile(path, mime string) error {
	f, err := os.Open(path)
	if err != nil {
		return axerr.Wrap(axerr.NotFound, err, "reading %s", path)
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() > MaxFile {
		return axerr.New(axerr.BadRequest, "%s isn't a file of at most %d bytes", path, MaxFile)
	}
	data := make([]byte, info.Size())
	if _, err := f.ReadAt(data, 0); err != nil && info.Size() > 0 {
		return axerr.Wrap(axerr.Unavailable, err, "reading %s", path)
	}
	return h.set([]string{mime}, data)
}

func (h *History) set(mimes []string, data []byte) error {
	if h.o.Set == nil {
		return axerr.New(axerr.Unavailable, "no clipboard here")
	}
	byMime := map[string][]byte{}
	for _, m := range mimes {
		byMime[m] = data
	}
	return h.o.Set(mimes, byMime)
}

// Types are the current selection's types.
func (h *History) Types() []string {
	if o := h.current(); o != nil {
		return o.Mimes()
	}
	return nil
}

// Save writes the current selection, as the first of mimes it has, to
// path (atomically, 0600), returning the type written: a pasted image
// for the chat.
func (h *History) Save(ctx context.Context, mimes []string, path string) (string, error) {
	o := h.current()
	if o == nil {
		return "", axerr.New(axerr.NotFound, "the clipboard is empty")
	}
	have := o.Mimes()
	i := slices.IndexFunc(mimes, func(m string) bool { return slices.Contains(have, m) })
	if i < 0 {
		return "", axerr.New(axerr.NotFound, "the clipboard holds none of %s", strings.Join(mimes, ", "))
	}
	data, err := o.Receive(ctx, mimes[i], MaxFile, 10*time.Second)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return "", axerr.Wrap(axerr.Unavailable, err, "making %s", filepath.Dir(path))
	}
	if err := fsx.WriteFile(path, data, 0o600); err != nil {
		return "", axerr.Wrap(axerr.Unavailable, err, "writing %s", path)
	}
	return mimes[i], nil
}

func (h *History) current() Offer {
	if h.o.Current == nil {
		return nil
	}
	return h.o.Current()
}

// record reads a selection and adds it on top.
func (h *History) record(ctx context.Context, o Offer) {
	h.mu.Lock()
	enabled := h.enabled
	h.mu.Unlock()
	if !enabled {
		return
	}
	mimes := o.Mimes()
	has := func(m string) bool { return slices.Contains(mimes, m) }
	if has(secretMime) {
		hint, err := o.Receive(ctx, secretMime, 64, readTimeout)
		if err != nil || strings.TrimSpace(string(hint)) == "secret" {
			return
		}
	}
	e, err := h.read(ctx, o, mimes, has)
	if err != nil {
		h.o.Log.Debug("clipboard: a clip wasn't recorded", "err", err)
		return
	}
	if e == nil {
		return
	}
	h.add(e)
}

// read reads the clip as the type preferred: an image, else text, else
// HTML that is just an image. nil: nothing worth keeping.
func (h *History) read(ctx context.Context, o Offer, mimes []string, has func(string) bool) (*entry, error) {
	img := firstOf(imageMimes, has)
	if img == "" {
		img = firstFunc(mimes, func(m string) bool { return strings.HasPrefix(m, "image/") })
	}
	if img != "" {
		data, err := o.Receive(ctx, img, MaxImage, readTimeout)
		if err != nil || len(data) == 0 {
			return nil, err
		}
		format := strings.TrimPrefix(strings.SplitN(img, ";", 2)[0], "image/")
		e := &entry{mime: img, hash: sha256.Sum256(data), bytes: len(data)}
		e.Format, e.Size = format, humanSize(len(data))
		if cfg, _, err := image.DecodeConfig(bytes.NewReader(data)); err == nil {
			e.Dimensions = fmt.Sprintf("%dx%d", cfg.Width, cfg.Height)
		}
		e.Text = "[[ image " + format + " ]]"
		return e, h.writeImage(e, data)
	}
	if text := firstOf(textMimes, has); text != "" {
		data, err := o.Receive(ctx, text, 4*MaxText, readTimeout)
		if err != nil {
			return nil, err
		}
		s := string(data)
		if !utf8.ValidString(s) || strings.TrimSpace(s) == "" || utf8.RuneCountInString(s) > MaxText {
			return nil, nil
		}
		return &entry{text: s, hash: sha256.Sum256(data)}, nil
	}
	if has("text/html") {
		data, err := o.Receive(ctx, "text/html", 4*MaxText, readTimeout)
		if err != nil {
			return nil, err
		}
		m := imgOnly.FindStringSubmatch(string(data))
		if m == nil {
			return nil, nil
		}
		e := &entry{text: string(data), hash: sha256.Sum256(data)}
		e.HTML = true
		if strings.HasPrefix(m[1], "https://") || strings.HasPrefix(m[1], "http://") {
			e.Image = m[1]
		}
		return e, nil
	}
	return nil, nil
}

// writeImage keeps an image's bytes as a file for the shell; the entry's
// id is given first.
func (h *History) writeImage(e *entry, data []byte) error {
	h.mu.Lock()
	h.next++
	e.ID = strconv.Itoa(h.next)
	h.mu.Unlock()
	if err := os.MkdirAll(filepath.Dir(h.o.Dir), 0o700); err != nil {
		return err
	}
	if err := xdg.PrivateDir(h.o.Dir, true); err != nil {
		return err
	}
	e.Image = filepath.Join(h.o.Dir, e.ID+"."+safeExt(e.Format))
	return fsx.WriteFile(e.Image, data, 0o600)
}

// add puts e on top, dropping an earlier copy of it, then trims.
func (h *History) add(e *entry) {
	h.mu.Lock()
	if !h.enabled {
		h.dropFile(e)
		h.mu.Unlock()
		return
	}
	if e.ID == "" {
		h.next++
		e.ID = strconv.Itoa(h.next)
	}
	e.Time = time.Now().UnixMilli()
	if e.Format == "" {
		e.Text = preview(e.text)
	}
	h.entries = slices.DeleteFunc(h.entries, func(old *entry) bool {
		if old.hash == e.hash && old.Format == e.Format && old.HTML == e.HTML {
			h.dropFile(old)
			return true
		}
		return false
	})
	h.entries = append([]*entry{e}, h.entries...)
	h.trim()
	h.mu.Unlock()
	h.changed()
}

// trim keeps max entries, and images within the byte budget (the oldest
// go first); h.mu is held.
func (h *History) trim() {
	for len(h.entries) > max(h.max, 0) {
		h.dropFile(h.entries[len(h.entries)-1])
		h.entries = h.entries[:len(h.entries)-1]
	}
	total := 0
	keep := h.entries[:0]
	for _, e := range h.entries {
		if e.bytes > 0 && total+e.bytes > ImageBudget {
			h.dropFile(e)
			continue
		}
		total += e.bytes
		keep = append(keep, e)
	}
	h.entries = keep
}

func (h *History) find(id string) *entry {
	for _, e := range h.entries {
		if e.ID == id {
			return e
		}
	}
	return nil
}

// dropFile removes an image's file; h.mu is held.
func (h *History) dropFile(e *entry) {
	if e.Format != "" && e.Image != "" {
		os.Remove(e.Image)
	}
}

// removeFiles empties the images' folder; h.mu is held.
func (h *History) removeFiles() {
	if h.o.Dir == "" {
		return
	}
	files, err := os.ReadDir(h.o.Dir)
	if errors.Is(err, fs.ErrNotExist) {
		return
	}
	for _, f := range files {
		os.Remove(filepath.Join(h.o.Dir, f.Name()))
	}
}

func (h *History) changed() {
	if h.o.OnChange != nil {
		h.o.OnChange()
	}
}

func firstOf(prefs []string, has func(string) bool) string {
	for _, m := range prefs {
		if has(m) {
			return m
		}
	}
	return ""
}

func firstFunc(list []string, fn func(string) bool) string {
	if i := slices.IndexFunc(list, fn); i >= 0 {
		return list[i]
	}
	return ""
}

// preview is a text's first PreviewLength characters.
func preview(s string) string {
	if utf8.RuneCountInString(s) <= PreviewLength {
		return s
	}
	return string([]rune(s)[:PreviewLength])
}

// safeExt is a format usable in a file name.
func safeExt(format string) string {
	ok := format != ""
	for _, r := range format {
		if !(r >= 'a' && r <= 'z' || r >= '0' && r <= '9' || r == '+' || r == '-') {
			ok = false
		}
	}
	if !ok {
		return "img"
	}
	return format
}

// humanSize is a byte count as people read it: "512 B", "1.2 MiB".
func humanSize(n int) string {
	switch {
	case n < 1<<10:
		return fmt.Sprintf("%d B", n)
	case n < 1<<20:
		return fmt.Sprintf("%.1f KiB", float64(n)/(1<<10))
	}
	return fmt.Sprintf("%.1f MiB", float64(n)/(1<<20))
}
