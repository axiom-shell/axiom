// Package axerr is the one error type that crosses axiom's boundaries: RPC
// replies, CLI exit codes and what the shell shows. A Kind says what went
// wrong in a way callers branch on (the shell translates by kind); the
// message stays English, like every log and validation error. Pure: no I/O.
package axerr

import (
	"errors"
	"fmt"
)

// Kind classifies an error for callers.
type Kind string

const (
	// Invalid input: a config, a value or a file that fails the schema.
	InvalidConfig Kind = "invalid_config"
	// The request was well formed but is wrong for the command (bad path,
	// unknown setting, malformed params).
	BadRequest Kind = "bad_request"
	// The state changed under the request (a `base` mismatch, a held lock).
	Conflict Kind = "conflict"
	// A takeover setting changed without the explicit opt-in.
	TakeoverRefused Kind = "takeover_refused"
	// The peer speaks another protocol or schema.
	Incompatible Kind = "incompatible"
	// Nothing to talk to: no daemon, no shell, no lock surface.
	Unavailable Kind = "unavailable"
	// Already running on this display.
	Running  Kind = "running"
	NotFound Kind = "not_found"
	// Refused on purpose (a security rule, a read-only calendar), never
	// retried.
	Refused Kind = "refused"
	// A server refused the credentials (or none are saved).
	Unauthorized Kind = "unauthorized"
	// A server's reply couldn't be read (not XML, not iCalendar).
	BadReply Kind = "bad_reply"
	// A bug or an unexpected system failure.
	Internal Kind = "internal"
)

// Issue is one reason a value fails validation, at a path into it.
type Issue struct {
	Path    string `json:"path"`
	Message string `json:"message"`
}

// Error is an error with a Kind, optional validation issues and an
// optional wrapped cause.
type Error struct {
	Kind    Kind
	Message string
	Issues  []Issue
	Err     error
}

func (e *Error) Error() string {
	if e.Err != nil && e.Message != "" {
		return e.Message + ": " + e.Err.Error()
	}
	if e.Err != nil {
		return e.Err.Error()
	}
	return e.Message
}

func (e *Error) Unwrap() error { return e.Err }

// New makes an Error of kind with a formatted message.
func New(kind Kind, format string, args ...any) *Error {
	return &Error{Kind: kind, Message: fmt.Sprintf(format, args...)}
}

// Wrap gives err a kind and context; nil stays nil.
func Wrap(kind Kind, err error, format string, args ...any) error {
	if err == nil {
		return nil
	}
	return &Error{Kind: kind, Message: fmt.Sprintf(format, args...), Err: err}
}

// KindOf is err's kind: the outermost *Error's, else Internal.
func KindOf(err error) Kind {
	var e *Error
	if errors.As(err, &e) {
		return e.Kind
	}
	return Internal
}

// IssuesOf collects the validation issues err carries.
func IssuesOf(err error) []Issue {
	var e *Error
	if errors.As(err, &e) {
		return e.Issues
	}
	return nil
}

// ExitCode is the CLI's exit status for err (0 for nil):
// 1 failed or invalid, 2 usage, 3 unavailable/incompatible/running,
// 4 conflict or refused.
func ExitCode(err error) int {
	if err == nil {
		return 0
	}
	switch KindOf(err) {
	case BadRequest:
		return 2
	case Unavailable, Incompatible, Running:
		return 3
	case Conflict, TakeoverRefused, Refused:
		return 4
	default:
		return 1
	}
}

// RPCCode maps a kind onto a JSON-RPC error code: -32602 (invalid params)
// for bad requests, -32603 for internal errors, and one code per kind in
// the implementation-defined range otherwise.
func RPCCode(kind Kind) int {
	switch kind {
	case BadRequest:
		return -32602
	case InvalidConfig:
		return -32001
	case Conflict:
		return -32002
	case TakeoverRefused:
		return -32003
	case Incompatible:
		return -32004
	case Unavailable:
		return -32005
	case Running:
		return -32006
	case NotFound:
		return -32007
	case Refused:
		return -32008
	case Unauthorized:
		return -32009
	case BadReply:
		return -32010
	default:
		return -32603
	}
}
