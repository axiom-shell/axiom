#!/usr/bin/env bash
# Dummy NetworkManager VPN profiles for testing axiom's VPN controls.
# Each is owned by this user (connection.permissions), so no admin rights
# are needed, never connects on its own, and can't reach anything:
#
#   Axiom test WireGuard   comes up for real (WireGuard has no handshake at
#                          connect), with a peer at 192.0.2.1 (TEST-NET-1)
#                          routing only 10.99.0.0/24
#   Axiom test OpenVPN     asks for a password on every connect, then times
#                          out against 192.0.2.1 (needs networkmanager-openvpn;
#                          without it, a profile whose connect fails with
#                          "plugin missing" instead)
#
#   scripts/dev/vpn-fixtures.sh up       add the profiles (replacing old ones)
#   scripts/dev/vpn-fixtures.sh down     delete every "Axiom test …" profile
#   scripts/dev/vpn-fixtures.sh status   list them
set -euo pipefail

prefix="Axiom test"
wg="$prefix WireGuard"
ovpn="$prefix OpenVPN"
owner="user:$(id -un)"

# A WireGuard key: 32 random bytes, clamped as Curve25519 wants
key() {
  python3 -I -c 'import os, base64
b = bytearray(os.urandom(32)); b[0] &= 248; b[31] = (b[31] & 127) | 64
print(base64.b64encode(bytes(b)).decode())'
}

ours() {
  nmcli -g NAME connection show | while IFS= read -r name; do
    if [[ "$name" == "$prefix "* ]]; then printf '%s\n' "$name"; fi
  done
}

down() {
  ours | while IFS= read -r name; do
    nmcli connection delete id "$name" >/dev/null && echo "deleted: $name"
  done
}

up() {
  down
  nmcli connection add type wireguard con-name "$wg" ifname wg-axtest \
    connection.autoconnect no connection.permissions "$owner" \
    ipv4.method manual ipv4.addresses 10.99.0.2/24 ipv4.never-default yes \
    ipv6.method disabled >/dev/null
  # The key and the peer only take once the profile exists
  nmcli connection modify "$wg" wireguard.private-key "$(key)"
  nmcli connection modify "$wg" wireguard.peers \
    "$(key) allowed-ips=10.99.0.0/24 endpoint=192.0.2.1:51820"
  echo "added: $wg"

  if [[ -e /usr/lib/NetworkManager/VPN/nm-openvpn-service.name ]]; then
    nmcli connection add type vpn con-name "$ovpn" vpn-type openvpn \
      connection.autoconnect no connection.permissions "$owner" \
      ipv4.never-default yes \
      vpn.data "remote=192.0.2.1, connection-type=password, username=axiomtest, password-flags=2, connect-timeout=10" \
      >/dev/null
    echo "added: $ovpn"
  else
    # NetworkManager stores a profile for a plugin it doesn't have; only
    # connecting fails
    nmcli connection add type vpn con-name "$ovpn (no plugin)" vpn-type openvpn \
      connection.autoconnect no connection.permissions "$owner" \
      vpn.data "remote=192.0.2.1, connection-type=password, username=axiomtest, password-flags=2" \
      >/dev/null 2>&1 && echo "added: $ovpn (no plugin)" ||
      echo "skipped: $ovpn (nmcli refuses openvpn without its plugin)"
    echo "for the password prompt: sudo pacman -S networkmanager-openvpn, then run up again"
  fi
}

case "${1:-}" in
up) up ;;
down) down ;;
status) nmcli -f NAME,TYPE,DEVICE,ACTIVE connection show | awk -v p="$prefix" 'NR == 1 || index($0, p) == 1' ;;
*) sed -n '2,17p' "$0" >&2; exit 2 ;;
esac
