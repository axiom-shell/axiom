// Package netif answers what the shell asks about a network interface
// (`net.addresses`, NetworkingManager): its IPv4 address, read from the
// kernel rather than through `ip`.
package netif

import "net"

// IPv4 is device's first IPv4 address, "" when it has none or doesn't
// exist (gone since the shell asked).
func IPv4(device string) string {
	iface, err := net.InterfaceByName(device)
	if err != nil {
		return ""
	}
	addrs, err := iface.Addrs()
	if err != nil {
		return ""
	}
	return firstIPv4(addrs)
}

func firstIPv4(addrs []net.Addr) string {
	for _, a := range addrs {
		if n, ok := a.(*net.IPNet); ok {
			if ip := n.IP.To4(); ip != nil {
				return ip.String()
			}
		}
	}
	return ""
}
