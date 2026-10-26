package wire

import (
	"os"

	"golang.org/x/sys/unix"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// SealedFile is data in an anonymous memory file, sealed so it can't
// change once the compositor maps it (a keymap, gamma ramps), ready to
// pass as an Fd. The caller closes it once sent.
func SealedFile(name string, data []byte) (*os.File, error) {
	fd, err := unix.MemfdCreate(name, unix.MFD_CLOEXEC|unix.MFD_ALLOW_SEALING)
	if err != nil {
		return nil, axerr.Wrap(axerr.Internal, err, "memfd_create")
	}
	f := os.NewFile(uintptr(fd), name)
	if _, err := f.Write(data); err != nil {
		f.Close()
		return nil, axerr.Wrap(axerr.Internal, err, "writing %s", name)
	}
	if _, err := f.Seek(0, 0); err != nil {
		f.Close()
		return nil, err
	}
	seals := unix.F_SEAL_SHRINK | unix.F_SEAL_GROW | unix.F_SEAL_WRITE | unix.F_SEAL_SEAL
	if _, err := unix.FcntlInt(f.Fd(), unix.F_ADD_SEALS, seals); err != nil {
		f.Close()
		return nil, axerr.Wrap(axerr.Internal, err, "sealing %s", name)
	}
	return f, nil
}
