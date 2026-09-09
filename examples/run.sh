#!/bin/bash
# Visualize Examples Server
#
# Usage: ./run.sh [<ip>:<port> | <ip> | <port>]
#
#   ./run.sh                 127.0.0.1:4080  (the default)
#   ./run.sh 4020            127.0.0.1:4020
#   ./run.sh 0.0.0.0         0.0.0.0:4080
#   ./run.sh 0.0.0.0:4020    0.0.0.0:4020
#
# An IPv6 literal is given in brackets: ./run.sh [::1]:4020

set -e

cd "$(dirname "$0")"

ip="127.0.0.1"
port="4080"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    bind="$1"
    # Split on the LAST colon, and only when what follows is a port, so that a bare
    # address — including an IPv6 literal — is not mistaken for one.
    if [[ "$bind" =~ ^(.*):([0-9]+)$ ]]; then
      ip="${BASH_REMATCH[1]}"
      port="${BASH_REMATCH[2]}"
    elif [[ "$bind" =~ ^[0-9]+$ ]]; then
      port="$bind"
    else
      ip="$bind"
    fi
    # A bracketed IPv6 literal is written [::1]; the endpoint wants it bare.
    ip="${ip#[}"
    ip="${ip%]}"
    [ -n "$ip" ] || ip="127.0.0.1"
    ;;
esac

export VISUALIZE_IP="$ip"
export VISUALIZE_PORT="$port"

echo "Installing dependencies..."
mix deps.get

echo "Compiling..."
mix compile

host="$ip"
case "$ip" in
  0.0.0.0 | ::) host="$(hostname -I 2>/dev/null | awk '{print $1}')" ;;
esac
[ -n "$host" ] || host="$ip"

echo ""
echo "Starting server at http://${host}:${port}"
case "$ip" in
  127.0.0.1 | ::1 | localhost) ;;
  *) echo "Bound to ${ip} — this development server has no authentication and is now" \
          "reachable by anything that can route to it." ;;
esac
echo "Press Ctrl+C to stop"
echo ""

mix phx.server
