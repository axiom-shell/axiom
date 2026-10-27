// Package theme generates the themes made from a wallpaper
// (ThemeManager's generateThemesFromWallpaper): it decodes the image
// (PNG, JPEG or BMP, the wallpapers axiom lists, or a WebP or GIF set by
// path), has package palette build every style's pair, and writes them to
// the generated themes' folder, each file atomically, so the shell's watch
// never reads half a theme.
package theme

import (
	"fmt"
	"image"
	_ "image/gif" // decoders, registered for image.Decode
	_ "image/jpeg"
	_ "image/png"
	"io"
	"os"
	"path/filepath"
	"time"

	_ "golang.org/x/image/bmp"
	_ "golang.org/x/image/webp"

	"github.com/axiom-shell/axiom/backend/internal/assets"
	"github.com/axiom-shell/axiom/backend/internal/axerr"
	"github.com/axiom-shell/axiom/backend/internal/fsx"
	"github.com/axiom-shell/axiom/backend/internal/jsonx"
	"github.com/axiom-shell/axiom/backend/internal/theme/palette"
)

// maxPixels bounds the image decoded whole (an 8K×8K one): the daemon
// decodes it in memory, so a larger one, or a header claiming one, is
// refused rather than allocated.
const maxPixels = 8192 * 8192

// Generate writes every style's wallpaper-<style>-dark|light.json made from
// the image at wallpaper into dir, and returns their paths. An image that
// can't be read is axerr.NotFound (no such file) or BadRequest (not an
// image it can decode, or larger than maxPixels); a write that fails,
// Unavailable.
func Generate(wallpaper, dir string, now time.Time) ([]string, error) {
	semantic, err := darkSemantic()
	if err != nil {
		return nil, err
	}
	path, err := filepath.Abs(wallpaper)
	if err != nil {
		return nil, axerr.Wrap(axerr.BadRequest, err, "can't read the wallpaper")
	}
	if resolved, err := filepath.EvalSymlinks(path); err == nil {
		path = resolved
	}
	f, err := os.Open(path)
	if err != nil {
		kind := axerr.Unavailable
		if os.IsNotExist(err) {
			kind = axerr.NotFound
		}
		return nil, axerr.Wrap(kind, err, "can't read the wallpaper")
	}
	img, err := decode(f)
	f.Close()
	if err != nil {
		return nil, axerr.Wrap(axerr.BadRequest, err, "can't read the wallpaper %s", path)
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, axerr.Wrap(axerr.Unavailable, err, "can't make the themes' folder")
	}
	var written []string
	for _, file := range palette.Themes(palette.Analyze(img), semantic, path, now) {
		out := filepath.Join(dir, file.Name)
		if err := fsx.WriteFile(out, file.Data, 0o644); err != nil {
			return written, err
		}
		written = append(written, out)
	}
	return written, nil
}

// decode reads the image after checking its header's size.
func decode(f *os.File) (image.Image, error) {
	cfg, _, err := image.DecodeConfig(f)
	if err != nil {
		return nil, err
	}
	if cfg.Width <= 0 || cfg.Height <= 0 || cfg.Width*cfg.Height > maxPixels {
		return nil, fmt.Errorf("a %d×%d image is too large or empty", cfg.Width, cfg.Height)
	}
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return nil, err
	}
	img, _, err := image.Decode(f)
	return img, err
}

// darkSemantic is theme-defaults.json's dark semantic map, which every
// generated theme starts from (background = base00, as every hand-made
// theme orders it).
func darkSemantic() (*jsonx.Object, error) {
	raw, err := assets.Read("config/json/theme-defaults.json")
	if err != nil {
		return nil, axerr.Wrap(axerr.Internal, err, "theme defaults")
	}
	v, err := jsonx.Unmarshal(raw)
	if err != nil {
		return nil, axerr.Wrap(axerr.Internal, err, "theme defaults")
	}
	if defaults, ok := v.(*jsonx.Object); ok {
		if semantic, ok := defaults.Value("semantic").(*jsonx.Object); ok {
			if dark, ok := semantic.Value("dark").(*jsonx.Object); ok {
				return dark, nil
			}
		}
	}
	return nil, axerr.New(axerr.Internal, "theme defaults have no dark semantic map")
}
