package dbus

import (
	"errors"
	"fmt"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
)

// Error names this package sends or tells apart
const (
	ErrUnknownMethod    = "org.freedesktop.DBus.Error.UnknownMethod"
	ErrUnknownObject    = "org.freedesktop.DBus.Error.UnknownObject"
	ErrUnknownInterface = "org.freedesktop.DBus.Error.UnknownInterface"
	ErrInvalidArgs      = "org.freedesktop.DBus.Error.InvalidArgs"
	ErrFailed           = "org.freedesktop.DBus.Error.Failed"
	ErrAccessDenied     = "org.freedesktop.DBus.Error.AccessDenied"
	ErrServiceUnknown   = "org.freedesktop.DBus.Error.ServiceUnknown"
	ErrNameHasNoOwner   = "org.freedesktop.DBus.Error.NameHasNoOwner"
	ErrNoReply          = "org.freedesktop.DBus.Error.NoReply"
	ErrLimitsExceeded   = "org.freedesktop.DBus.Error.LimitsExceeded"
)

// Error is an error reply: its name and message.
type Error struct {
	Name    string
	Message string
}

func (e *Error) Error() string {
	if e.Message == "" {
		return e.Name
	}
	return e.Name + ": " + e.Message
}

// NewError is an error reply to send from a method handler.
func NewError(name, format string, args ...any) *Error {
	return &Error{Name: name, Message: fmt.Sprintf(format, args...)}
}

// ErrorName is err's D-Bus error name, "" when it isn't a reply's.
func ErrorName(err error) string {
	var e *Error
	if errors.As(err, &e) {
		return e.Name
	}
	return ""
}

// kindOf is the axerr kind an error reply crosses axiom's boundaries as.
func kindOf(name string) axerr.Kind {
	switch name {
	case ErrServiceUnknown, ErrNameHasNoOwner, ErrNoReply, "org.freedesktop.DBus.Error.Disconnected", "org.freedesktop.DBus.Error.Timeout":
		return axerr.Unavailable
	case ErrAccessDenied, "org.freedesktop.DBus.Error.InteractiveAuthorizationRequired":
		return axerr.Refused
	case ErrUnknownMethod, ErrUnknownObject, ErrUnknownInterface, ErrInvalidArgs:
		return axerr.BadRequest
	}
	return axerr.Internal
}
