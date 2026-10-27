// Package brightness reads and sets the monitors' brightness for the
// shell's BrightnessManager (`brightness.*`): a laptop panel's backlight
// read from /sys/class/backlight and set through logind's
// Session.SetBrightness (how a session's user may write it without
// access to sysfs, as brightnessctl does), and external monitors over
// DDC/CI (VCP 0x10) with ddcutil, which stays a program.
package brightness

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/dbus"
	"github.com/axiom-shell/axiom/backend/internal/logind"
)

// Kinds of controller
const (
	KindBacklight = "backlight"
	KindDDC       = "ddc"
)

// ddcutil can take seconds on a slow monitor; never longer than this
const ddcTimeout = 10 * time.Second

var (
	// A backlight's name in sysfs: never a path
	validDevice = regexp.MustCompile(`^[\w.:+-]+$`)
	// One display in `ddcutil detect --terse`
	displayHeader = regexp.MustCompile(`^Display \d+`)
	i2cBus        = regexp.MustCompile(`I2C bus:\s*/dev/i2c-(\d+)`)
	drmConnector  = regexp.MustCompile(`DRM connector:\s*card\d+-(\S+)`)
	// `ddcutil getvcp 10 --terse`: "VCP 10 C <current> <max>"
	vcpLevel = regexp.MustCompile(`VCP 10 C (\d+) (\d+)`)
)

// Several backlights can drive one panel: firmware first, then platform,
// then raw, as systemd-backlight picks
var backlightPriority = map[string]int{"firmware": 0, "platform": 1, "raw": 2}

// Target is one controller, as the shell names it.
type Target struct {
	Kind   string `json:"kind"`   // KindBacklight or KindDDC
	Device string `json:"device"` // a backlight's name in sysfs
	Bus    int    `json:"bus"`    // a monitor's I2C bus, /dev/i2c-<bus>
}

// Level is a brightness: Value out of Max.
type Level struct {
	Value int `json:"value"`
	Max   int `json:"max"`
}

// Backlight is the panel's backlight with its level.
type Backlight struct {
	Device string `json:"device"`
	Level
}

// DDC is a monitor answering DDC/CI.
type DDC struct {
	Bus       int    `json:"bus"`
	Connector string `json:"connector"` // the DRM connector, "DP-1"
}

// Found is what Detect found.
type Found struct {
	Backlight *Backlight `json:"backlight"` // nil: none
	DDC       []DDC      `json:"ddc"`
}

// Options are where the controllers are; zero values are the real ones.
type Options struct {
	// Dir holds the backlights ("" is /sys/class/backlight)
	Dir string
	// Run runs ddcutil with args and returns its stdout
	Run func(ctx context.Context, args ...string) ([]byte, error)
	// SystemBus connects to the system bus, for logind
	SystemBus func(ctx context.Context) (*dbus.Conn, error)
	Getenv    func(string) string
}

// Service answers the shell's brightness calls.
type Service struct {
	o Options
}

// New is a service on o.
func New(o Options) *Service {
	if o.Dir == "" {
		o.Dir = "/sys/class/backlight"
	}
	if o.Run == nil {
		o.Run = ddcutil
	}
	return &Service{o: o}
}

func ddcutil(ctx context.Context, args ...string) ([]byte, error) {
	if _, err := exec.LookPath("ddcutil"); err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "ddcutil isn't installed")
	}
	var stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, "ddcutil", args...)
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return out, axerr.Wrap(axerr.Unavailable, err, "ddcutil %s: %s", strings.Join(args, " "), strings.TrimSpace(stderr.String()))
	}
	return out, nil
}

// Detect finds the panel's backlight and the monitors answering DDC/CI
// (without their levels: reading each is slow, Get does it).
func (s *Service) Detect(ctx context.Context) Found {
	ctx, cancel := context.WithTimeout(ctx, ddcTimeout)
	defer cancel()
	// Without ddcutil, or with no monitor answering, there are none
	out, _ := s.o.Run(ctx, "detect", "--terse")
	return Found{Backlight: s.backlight(), DDC: parseDetect(string(out))}
}

func (s *Service) backlight() *Backlight {
	entries, _ := os.ReadDir(s.o.Dir)
	type candidate struct {
		b    Backlight
		rank int
	}
	var all []candidate
	for _, e := range entries {
		if !validDevice.MatchString(e.Name()) {
			continue
		}
		level, err := s.readLevel(e.Name())
		if err != nil {
			continue
		}
		rank, ok := backlightPriority[s.read(e.Name(), "type")]
		if !ok {
			rank = len(backlightPriority)
		}
		all = append(all, candidate{Backlight{e.Name(), level}, rank})
	}
	if len(all) == 0 {
		return nil
	}
	best := slices.MinFunc(all, func(a, b candidate) int {
		if a.rank != b.rank {
			return a.rank - b.rank
		}
		return strings.Compare(a.b.Device, b.b.Device)
	})
	return &best.b
}

func (s *Service) read(device, file string) string {
	b, _ := os.ReadFile(filepath.Join(s.o.Dir, device, file))
	return strings.TrimSpace(string(b))
}

func (s *Service) readLevel(device string) (Level, error) {
	value, err1 := strconv.Atoi(s.read(device, "brightness"))
	top, err2 := strconv.Atoi(s.read(device, "max_brightness"))
	if err := errors.Join(err1, err2); err != nil {
		return Level{}, axerr.Wrap(axerr.NotFound, err, "backlight %q", device)
	}
	return Level{Value: value, Max: top}, nil
}

// parseDetect reads `ddcutil detect --terse`: each "Display N" block's
// I2C bus and DRM connector; blocks without both (an invalid display, a
// laptop panel) are left out.
func parseDetect(text string) []DDC {
	out := []DDC{}
	var block []string
	flush := func() {
		joined := strings.Join(block, "\n")
		bus := i2cBus.FindStringSubmatch(joined)
		conn := drmConnector.FindStringSubmatch(joined)
		if bus != nil && conn != nil {
			n, _ := strconv.Atoi(bus[1])
			out = append(out, DDC{Bus: n, Connector: conn[1]})
		}
		block = nil
	}
	in := false
	for _, line := range strings.Split(text, "\n") {
		switch {
		case displayHeader.MatchString(line):
			flush()
			in = true
		case line != "" && line[0] != ' ' && line[0] != '\t':
			// Another header ("Invalid display") ends the block
			flush()
			in = false
		case in:
			block = append(block, line)
		}
	}
	flush()
	return out
}

// Get reads a controller's level.
func (s *Service) Get(ctx context.Context, t Target) (Level, error) {
	switch t.Kind {
	case KindBacklight:
		if !validDevice.MatchString(t.Device) {
			return Level{}, axerr.New(axerr.BadRequest, "brightness: bad backlight %q", t.Device)
		}
		return s.readLevel(t.Device)
	case KindDDC:
		ctx, cancel := context.WithTimeout(ctx, ddcTimeout)
		defer cancel()
		out, err := s.o.Run(ctx, "--bus", strconv.Itoa(t.Bus), "getvcp", "10", "--terse")
		if err != nil {
			return Level{}, err
		}
		m := vcpLevel.FindStringSubmatch(string(out))
		if m == nil {
			return Level{}, axerr.New(axerr.Unavailable, "brightness: no VCP 10 from bus %d", t.Bus)
		}
		value, _ := strconv.Atoi(m[1])
		top, _ := strconv.Atoi(m[2])
		return Level{Value: value, Max: top}, nil
	}
	return Level{}, axerr.New(axerr.BadRequest, "brightness: unknown kind %q", t.Kind)
}

// Set sets a controller to value (out of its max).
func (s *Service) Set(ctx context.Context, t Target, value int) error {
	if value < 0 {
		return axerr.New(axerr.BadRequest, "brightness: negative value %d", value)
	}
	switch t.Kind {
	case KindBacklight:
		if !validDevice.MatchString(t.Device) {
			return axerr.New(axerr.BadRequest, "brightness: bad backlight %q", t.Device)
		}
		return s.setBacklight(ctx, t.Device, uint32(value))
	case KindDDC:
		ctx, cancel := context.WithTimeout(ctx, ddcTimeout)
		defer cancel()
		_, err := s.o.Run(ctx, "--bus", strconv.Itoa(t.Bus), "--noverify", "setvcp", "10", strconv.Itoa(value))
		return err
	}
	return axerr.New(axerr.BadRequest, "brightness: unknown kind %q", t.Kind)
}

// setBacklight asks logind on a connection of its own: the shell sends
// one set at a time per monitor, so dialling each time costs nothing
func (s *Service) setBacklight(ctx context.Context, device string, value uint32) error {
	if s.o.SystemBus == nil {
		return axerr.New(axerr.Unavailable, "brightness: no system bus")
	}
	conn, err := s.o.SystemBus(ctx)
	if err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "brightness: connecting to the system bus")
	}
	defer conn.Close()
	lg, err := logind.Open(ctx, conn, s.o.Getenv)
	if err != nil {
		return err
	}
	if err := lg.SetBrightness(ctx, KindBacklight, device, value); err != nil {
		return axerr.Wrap(axerr.Unavailable, err, "logind: setting backlight %q", device)
	}
	return nil
}
