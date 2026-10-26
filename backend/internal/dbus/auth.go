package dbus

import (
	"bufio"
	"encoding/hex"
	"fmt"
	"io"
	"strconv"
	"strings"
)

// authenticate runs the client side of SASL EXTERNAL (the kernel vouches
// for our uid), then asks to pass descriptors. It reads a byte at a
// time from r, so nothing past BEGIN is read into a buffer the message
// reader won't see; it reports whether the bus agreed to descriptors.
func authenticate(w io.Writer, r io.Reader, uid int) (bool, error) {
	br := bufio.NewReaderSize(oneByte{r}, 16)
	line := func() (string, error) {
		s, err := br.ReadString('\n')
		if len(s) > 512 {
			return "", fmt.Errorf("dbus: an auth line too long")
		}
		return strings.TrimRight(s, "\r\n"), err
	}
	send := func(s string) error {
		_, err := io.WriteString(w, s+"\r\n")
		return err
	}
	// The NUL byte that starts every connection
	if _, err := w.Write([]byte{0}); err != nil {
		return false, err
	}
	if err := send("AUTH EXTERNAL " + hex.EncodeToString([]byte(strconv.Itoa(uid)))); err != nil {
		return false, err
	}
	reply, err := line()
	if err != nil {
		return false, err
	}
	if !strings.HasPrefix(reply, "OK ") {
		return false, fmt.Errorf("dbus: the bus refused EXTERNAL auth: %q", reply)
	}
	if err := send("NEGOTIATE_UNIX_FD"); err != nil {
		return false, err
	}
	reply, err = line()
	if err != nil {
		return false, err
	}
	fds := reply == "AGREE_UNIX_FD"
	return fds, send("BEGIN")
}

// oneByte reads at most one byte per Read, so a bufio.Reader over it
// never reads ahead of the line it returns.
type oneByte struct{ r io.Reader }

func (o oneByte) Read(p []byte) (int, error) {
	if len(p) > 1 {
		p = p[:1]
	}
	return o.r.Read(p)
}
