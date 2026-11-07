package bluez

import (
	"encoding/binary"
	"errors"
	"io"
	"io/fs"
	"os"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// The kernel's rfkill interface (linux/rfkill.h)
const (
	rfkillTypeBluetooth = 2
	rfkillOpChangeAll   = 3
)

// rfkillEvent is struct rfkill_event (the first version, 8 bytes, which
// every kernel takes): idx, type, op, soft, hard.
func rfkillEvent(typ, op, soft uint8) []byte {
	b := make([]byte, 8)
	binary.NativeEndian.PutUint32(b, 0)
	b[4], b[5], b[6], b[7] = typ, op, soft, 0
	return b
}

func openRfkill() (io.WriteCloser, error) {
	return os.OpenFile("/dev/rfkill", os.O_WRONLY, 0)
}

// Unblock clears the soft rfkill block of every Bluetooth radio, as
// `rfkill unblock bluetooth` does: one change-all event written to
// /dev/rfkill, which the session's user may write (logind's uaccess ACL),
// so no root. A hardware switch's block can't be cleared from software:
// that's refused, saying so. BlueZ powers the adapter back on if it was
// on before the block.
func (s *Service) Unblock() error {
	if a := s.State().Adapter; a != nil && a.HardBlocked {
		return axerr.New(axerr.Refused, "a hardware switch blocks Bluetooth: turn it on to unblock it")
	}
	w, err := s.o.RfkillDev()
	if err != nil {
		switch {
		case errors.Is(err, fs.ErrPermission):
			return axerr.Wrap(axerr.NotAuthorized, err, "writing /dev/rfkill")
		case errors.Is(err, fs.ErrNotExist):
			return axerr.Wrap(axerr.Unavailable, err, "no rfkill device")
		}
		return axerr.Wrap(axerr.Failed, err, "opening /dev/rfkill")
	}
	_, err = w.Write(rfkillEvent(rfkillTypeBluetooth, rfkillOpChangeAll, 0))
	if cerr := w.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return axerr.Wrap(axerr.Failed, err, "writing /dev/rfkill")
	}
	// Read again: a BlueZ without PowerState sends nothing as rfkill
	// changes
	select {
	case s.kick <- struct{}{}:
	default:
	}
	return nil
}
