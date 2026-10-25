package netif

import (
	"net"
	"testing"
)

func TestFirstIPv4(t *testing.T) {
	t.Parallel()
	v6 := &net.IPNet{IP: net.ParseIP("fe80::1"), Mask: net.CIDRMask(64, 128)}
	v4 := &net.IPNet{IP: net.ParseIP("192.168.8.204"), Mask: net.CIDRMask(24, 32)}
	cases := []struct {
		name  string
		addrs []net.Addr
		want  string
	}{
		{"none", nil, ""},
		{"only v6", []net.Addr{v6}, ""},
		{"v6 first", []net.Addr{v6, v4}, "192.168.8.204"},
		{"not an IPNet", []net.Addr{&net.IPAddr{IP: net.ParseIP("10.0.0.1")}}, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := firstIPv4(tc.addrs); got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

func TestIPv4(t *testing.T) {
	t.Parallel()
	if got := IPv4("lo"); got != "127.0.0.1" && got != "" {
		t.Errorf("lo: %q", got)
	}
	if got := IPv4("no-such-interface0"); got != "" {
		t.Errorf("a missing interface: %q", got)
	}
}
