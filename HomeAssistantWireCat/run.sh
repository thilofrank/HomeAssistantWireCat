#!/usr/bin/env bash
set -e

OPTIONS_FILE="/data/options.json"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "=== WireGuard Gateway Add-On Starting ==="

if [ ! -f "$OPTIONS_FILE" ]; then
    log "ERROR: Options file not found at $OPTIONS_FILE"
    exit 1
fi

# ---------------------------------------------------------------------------
# Read configuration from HA options
# ---------------------------------------------------------------------------
ADDRESS=$(jq -r '.interface.Address' "$OPTIONS_FILE")
PEER_PUBKEY=$(jq -r '.peer.PublicKey' "$OPTIONS_FILE")
ALLOWED_IPS=$(jq -r '.peer.AllowedIPs' "$OPTIONS_FILE")
ENDPOINT=$(jq -r '.peer.Endpoint' "$OPTIONS_FILE")
KEEPALIVE=$(jq -r '.peer.PersistentKeepalive' "$OPTIONS_FILE")

# Validate required fields
if [ -z "$PEER_PUBKEY" ] || [ "$PEER_PUBKEY" = "null" ]; then
    log "ERROR: peer.PublicKey is required but not configured"
    exit 1
fi
if [ -z "$ENDPOINT" ] || [ "$ENDPOINT" = "null" ]; then
    log "ERROR: peer.Endpoint is required but not configured"
    exit 1
fi

# ---------------------------------------------------------------------------
# Persistent directories
# These live under /data (HA Supervisor persistent storage).
# /config/wg_confs and /config/wgcat are symlinked to /data equivalents
# so the linuxserver/wireguard path convention is also satisfied.
# ---------------------------------------------------------------------------
mkdir -p /data/wgcat /data/wg_confs

# Symlink /config -> /data so paths like /config/wg_confs work as expected
if [ ! -L /config ]; then
    if [ -d /config ]; then
        cp -rp /config/. /data/ 2>/dev/null || true
        rm -rf /config
    fi
    ln -sf /data /config
fi

PRIVKEY_FILE="/data/wgcat/privatekey"
PUBKEY_FILE="/data/wgcat/publickey"
WG_CONF="/data/wg_confs/wg0.conf"

# ---------------------------------------------------------------------------
# Key management — generate once, persist forever
# ---------------------------------------------------------------------------
if [ ! -f "$PRIVKEY_FILE" ] || [ ! -f "$PUBKEY_FILE" ]; then
    log "Generating new WireGuard key pair..."
    wg genkey | tee "$PRIVKEY_FILE" | wg pubkey > "$PUBKEY_FILE"
    chmod 600 "$PRIVKEY_FILE"
    log "Key pair generated and stored in /config/wgcat"
fi

PRIVKEY=$(cat "$PRIVKEY_FILE")
PUBKEY=$(cat "$PUBKEY_FILE")
log "WireGuard public key: $PUBKEY"
log "(Ensure this public key is added as a peer on your WireGuard server)"

# ---------------------------------------------------------------------------
# Build wg0.conf
# ---------------------------------------------------------------------------
cat > "$WG_CONF" << EOF
[Interface]
Address = ${ADDRESS}
PrivateKey = ${PRIVKEY}

[Peer]
PublicKey = ${PEER_PUBKEY}
AllowedIPs = ${ALLOWED_IPS}
Endpoint = ${ENDPOINT}
PersistentKeepalive = ${KEEPALIVE}
EOF
chmod 600 "$WG_CONF"
log "wg0.conf written to /config/wg_confs/wg0.conf"

# ---------------------------------------------------------------------------
# Load kernel module (may already be built-in on HA OS)
# ---------------------------------------------------------------------------
modprobe wireguard 2>/dev/null || log "wireguard module already loaded or built-in"

# ---------------------------------------------------------------------------
# Start WireGuard
# ---------------------------------------------------------------------------
log "Bringing up WireGuard interface wg0..."
wg-quick up "$WG_CONF"
log "WireGuard interface wg0 is up"

# ---------------------------------------------------------------------------
# Start Socat tunnels
# ---------------------------------------------------------------------------
TUNNEL_COUNT=$(jq -r '.socat_tunnels | length' "$OPTIONS_FILE")

if [ "$TUNNEL_COUNT" -gt 0 ]; then
    log "Starting ${TUNNEL_COUNT} Socat tunnel(s)..."
    for i in $(seq 0 $((TUNNEL_COUNT - 1))); do
        INCOMING_PORT=$(jq -r ".socat_tunnels[$i].IncomingPort" "$OPTIONS_FILE")
        OUTGOING_ADDR=$(jq -r ".socat_tunnels[$i].OutgoingAddressPort" "$OPTIONS_FILE")
        log "  Tunnel $((i + 1)): 0.0.0.0:${INCOMING_PORT} -> ${OUTGOING_ADDR}"
        socat TCP-LISTEN:${INCOMING_PORT},reuseaddr,fork TCP:${OUTGOING_ADDR} &
    done
else
    log "No Socat tunnels configured"
fi

log "=== All services started ==="

# ---------------------------------------------------------------------------
# Cleanup on container stop
# ---------------------------------------------------------------------------
cleanup() {
    log "Shutting down..."
    wg-quick down "$WG_CONF" 2>/dev/null || true
    kill $(jobs -p) 2>/dev/null || true
    log "Shutdown complete"
}
trap cleanup EXIT SIGTERM SIGINT

# ---------------------------------------------------------------------------
# Monitor loop — restart WireGuard if it goes down
# ---------------------------------------------------------------------------
while true; do
    if ! wg show wg0 > /dev/null 2>&1; then
        log "WARNING: wg0 interface is down — restarting..."
        wg-quick down "$WG_CONF" 2>/dev/null || true
        sleep 2
        wg-quick up "$WG_CONF"
    fi
    sleep 30
done
