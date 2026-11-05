package account

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Why a password change failed
const (
	ReasonWrong    = "wrong"    // the current password was wrong
	ReasonWeak     = "weak"     // the new one was refused (too short, a word, …)
	ReasonMismatch = "mismatch" // the two new ones differ (passwd's own check)
	ReasonFailed   = "failed"   // anything else, Message says what
)

// PasswordResult is how a change went: OK, or why not (Reason) with
// passwd's own words (Message; never a password).
type PasswordResult struct {
	OK      bool   `json:"ok"`
	Reason  string `json:"reason,omitempty"`
	Message string `json:"message,omitempty"`
}

// How long passwd gets to ask its next question
const promptWait = 10 * time.Second

var (
	// A prompt: a line ending in "password:" (any words before it)
	promptPattern = regexp.MustCompile(`(?i)password[^:\n]*:\s*$`)
	retypePattern = regexp.MustCompile(`(?i)retype|again|confirm|repeat`)
	newPattern    = regexp.MustCompile(`(?i)\bnew\b`)
	// pam_pwquality's and pam_cracklib's refusal
	badPattern = regexp.MustCompile(`(?im)BAD PASSWORD:\s*(.+?)\s*$`)
	// A wrong current password, as pam_unix says it
	wrongPattern    = regexp.MustCompile(`(?i)authentication token manipulation error|authentication failure|incorrect password`)
	mismatchPattern = regexp.MustCompile(`(?i)do not match|don't match|mismatch`)
)

// ChangePassword changes the user's password with passwd, answering its
// questions through a pty (passwd reads from the terminal, never a pipe):
// the current password, then the new one twice. The passwords go only to
// passwd's terminal, and nothing it prints is logged.
func (a *Accounts) ChangePassword(ctx context.Context, current, next string) (PasswordResult, error) {
	if next == "" {
		return PasswordResult{Reason: ReasonWeak, Message: "The new password is empty."}, nil
	}
	if strings.ContainsAny(current+next, "\n\r\x00") {
		return PasswordResult{}, axerr.New(axerr.BadRequest, "a password can't hold a new line")
	}
	ctx, cancel := context.WithTimeout(ctx, a.o.PasswordTimeout)
	defer cancel()
	ptmx, pts, err := openPTY()
	if err != nil {
		return PasswordResult{}, axerr.Wrap(axerr.Unavailable, err, "opening a terminal for passwd")
	}
	defer ptmx.Close()
	cmd := exec.CommandContext(ctx, a.o.Passwd[0], a.o.Passwd[1:]...)
	// Its messages in English, so they can be read
	cmd.Env = append(os.Environ(), "LC_ALL=C", "LANG=C")
	cmd.Stdin, cmd.Stdout, cmd.Stderr = pts, pts, pts
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true, Ctty: 0}
	if err := cmd.Start(); err != nil {
		pts.Close()
		return PasswordResult{}, axerr.Wrap(axerr.Unavailable, err, "starting passwd")
	}
	pts.Close()
	out := newTranscript(ptmx)
	answered, news := 0, 0
	for {
		prompt, ok := out.next(ctx, promptWait)
		if !ok {
			break
		}
		var answer string
		switch {
		case retypePattern.MatchString(prompt):
			answer = next
		case newPattern.MatchString(prompt):
			// A second "New password:" is passwd asking again after
			// refusing the first: say why instead of going round
			if news++; news > 1 {
				cmd.Process.Kill()
				cmd.Wait()
				return refused(out.text()), nil
			}
			answer = next
		default:
			// The current password, asked once; asked again, it was wrong
			if answered > 0 && news == 0 {
				cmd.Process.Kill()
				cmd.Wait()
				return PasswordResult{Reason: ReasonWrong, Message: "The current password is wrong."}, nil
			}
			answer = current
		}
		answered++
		if _, err := ptmx.Write([]byte(answer + "\n")); err != nil {
			break
		}
	}
	err = cmd.Wait()
	text := out.text()
	if ctx.Err() != nil {
		return PasswordResult{Reason: ReasonFailed, Message: "passwd didn't finish in time."}, nil
	}
	if err == nil {
		return PasswordResult{OK: true}, nil
	}
	return refused(text), nil
}

// refused reads why passwd said no.
func refused(text string) PasswordResult {
	switch {
	case badPattern.MatchString(text):
		return PasswordResult{Reason: ReasonWeak, Message: badPattern.FindStringSubmatch(text)[1]}
	case mismatchPattern.MatchString(text):
		return PasswordResult{Reason: ReasonMismatch, Message: "The new passwords don't match."}
	case wrongPattern.MatchString(text):
		return PasswordResult{Reason: ReasonWrong, Message: "The current password is wrong."}
	}
	return PasswordResult{Reason: ReasonFailed, Message: lastLine(text)}
}

// lastLine is passwd's last words ("passwd: …"), for an error it has no
// reading of
func lastLine(text string) string {
	lines := strings.Split(strings.TrimSpace(text), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if line := strings.TrimSpace(lines[i]); line != "" && !promptPattern.MatchString(line) {
			return line
		}
	}
	return "passwd failed."
}

// transcript collects what passwd prints, read in the background.
type transcript struct {
	mu      sync.Mutex
	buf     strings.Builder
	from    int // where the next prompt is looked for
	changed chan struct{}
	done    chan struct{}
}

func newTranscript(f *os.File) *transcript {
	t := &transcript{changed: make(chan struct{}, 1), done: make(chan struct{})}
	go func() {
		defer close(t.done)
		b := make([]byte, 4096)
		for {
			n, err := f.Read(b)
			if n > 0 {
				t.mu.Lock()
				t.buf.Write(b[:n])
				t.mu.Unlock()
				select {
				case t.changed <- struct{}{}:
				default:
				}
			}
			if err != nil {
				// EIO once passwd has gone and the terminal closed
				return
			}
		}
	}()
	return t
}

// next waits for the next prompt (the text since the last one, ending in
// "password:"); false when passwd ends, ctx does or wait passes.
func (t *transcript) next(ctx context.Context, wait time.Duration) (string, bool) {
	timer := time.NewTimer(wait)
	defer timer.Stop()
	for {
		t.mu.Lock()
		rest := t.buf.String()[t.from:]
		if promptPattern.MatchString(rest) {
			t.from = t.buf.Len()
			t.mu.Unlock()
			return rest, true
		}
		t.mu.Unlock()
		select {
		case <-t.changed:
		case <-t.done:
			return "", false
		case <-ctx.Done():
			return "", false
		case <-timer.C:
			return "", false
		}
	}
}

func (t *transcript) text() string {
	// What's left to read lands before passwd's exit is reported
	select {
	case <-t.done:
	case <-time.After(200 * time.Millisecond):
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.buf.String()
}

// openPTY opens a pseudo-terminal: its controlling side and the terminal
// a child gets.
func openPTY() (*os.File, *os.File, error) {
	ptmx, err := os.OpenFile("/dev/ptmx", os.O_RDWR|syscall.O_NOCTTY|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, nil, err
	}
	fd := int(ptmx.Fd())
	if err := unix.IoctlSetPointerInt(fd, unix.TIOCSPTLCK, 0); err != nil {
		ptmx.Close()
		return nil, nil, fmt.Errorf("unlocking the terminal: %w", err)
	}
	n, err := unix.IoctlGetInt(fd, unix.TIOCGPTN)
	if err != nil {
		ptmx.Close()
		return nil, nil, fmt.Errorf("naming the terminal: %w", err)
	}
	pts, err := os.OpenFile(fmt.Sprintf("/dev/pts/%d", n), os.O_RDWR|syscall.O_NOCTTY|syscall.O_CLOEXEC, 0)
	if err != nil {
		ptmx.Close()
		return nil, nil, errors.Join(errors.New("opening the terminal"), err)
	}
	// No echo, so an answer never shows in what passwd prints (passwd
	// turns it off itself; a prompt before it does mustn't echo either)
	if t, err := unix.IoctlGetTermios(int(pts.Fd()), unix.TCGETS); err == nil {
		t.Lflag &^= unix.ECHO | unix.ECHONL
		unix.IoctlSetTermios(int(pts.Fd()), unix.TCSETS, t)
	}
	return ptmx, pts, nil
}
