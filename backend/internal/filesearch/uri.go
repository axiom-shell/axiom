package filesearch

import "strings"

// FileURI is the file:// URI of an absolute path, escaped as GLib's
// g_filename_to_uri escapes it: the thumbnail spec names a thumbnail by
// the md5 of this exact text, so a file manager's thumbnails are found.
func FileURI(path string) string {
	var b strings.Builder
	b.WriteString("file://")
	const hex = "0123456789ABCDEF"
	for i := 0; i < len(path); i++ {
		c := path[i]
		if uriSafe(c) {
			b.WriteByte(c)
			continue
		}
		b.WriteByte('%')
		b.WriteByte(hex[c>>4])
		b.WriteByte(hex[c&15])
	}
	return b.String()
}

// uriSafe: what g_filename_to_uri leaves as is (gconvert.c's table for
// UNSAFE_PATH): unreserved, or reserved but allowed in a path, except ;
func uriSafe(c byte) bool {
	switch {
	case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		return true
	}
	return strings.IndexByte("-._~!$&'()*+,=:@/", c) >= 0
}

// PathOfURI is the path a file:// URI names ("" for another scheme, or
// another host than this one).
func PathOfURI(uri string) string {
	rest, ok := strings.CutPrefix(uri, "file://")
	if !ok {
		return ""
	}
	if host, after, found := strings.Cut(rest, "/"); found && host != "" && host != "localhost" {
		return ""
	} else if found {
		rest = "/" + after
	} else {
		return ""
	}
	var b strings.Builder
	for i := 0; i < len(rest); i++ {
		if rest[i] == '%' && i+2 < len(rest) {
			if v, ok := unhex(rest[i+1], rest[i+2]); ok {
				b.WriteByte(v)
				i += 2
				continue
			}
		}
		b.WriteByte(rest[i])
	}
	return b.String()
}

func unhex(a, b byte) (byte, bool) {
	d := func(c byte) (byte, bool) {
		switch {
		case c >= '0' && c <= '9':
			return c - '0', true
		case c >= 'a' && c <= 'f':
			return c - 'a' + 10, true
		case c >= 'A' && c <= 'F':
			return c - 'A' + 10, true
		}
		return 0, false
	}
	x, ok1 := d(a)
	y, ok2 := d(b)
	return x<<4 | y, ok1 && ok2
}
