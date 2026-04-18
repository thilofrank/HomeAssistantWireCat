# WireGuard Gateway — Home Assistant Add-on

A Home Assistant add-on that establishes a WireGuard VPN tunnel to a remote relay server (e.g., a VPS) and forwards TCP ports through that tunnel using Socat. This lets you expose local services (like Home Assistant itself) to the internet without opening ports in your home router.

## Architecture

```
Internet
   │
   ▼
[ VPS / Relay ]  ◄──── WireGuard tunnel ────►  [ Home Assistant Add-on ]
  (public IP)                                        (behind NAT)
       │
       │  Socat port-forward
       ▼
 External clients reach your local services via the VPS
```

The HA add-on acts as the **WireGuard client**. It initiates the connection to the VPS, so no inbound firewall rules are needed on your home network. The VPS acts as the **relay**: traffic arriving on a public port is forwarded through the tunnel to the local service.

---

## Part 1 — VPS WireGuard Server Setup

### 1.1 Install WireGuard

```bash
apt update && apt install -y wireguard
```

### 1.2 Generate server keys

```bash
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
chmod 600 /etc/wireguard/server_private.key
```

### 1.3 Create `/etc/wireguard/wg0.conf`

```ini
[Interface]
Address    = 10.0.0.1/24
ListenPort = 5005
PrivateKey = <SERVER_PRIVATE_KEY>

# Enable IP forwarding / NAT if you want to route traffic through the VPS
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# Home Assistant client
[Peer]
PublicKey  = <HA_ADDON_PUBLIC_KEY>   # see Section 2.3
AllowedIPs = 10.0.0.2/32
```

> Replace `<SERVER_PRIVATE_KEY>` with the content of `server_private.key`.  
> Replace `<HA_ADDON_PUBLIC_KEY>` with the public key logged by the add-on on first start (see [Section 2.3](#23-retrieve-the-add-on-public-key)).  
> Adjust `eth0` to match your VPS network interface name.

### 1.4 Enable and start WireGuard

```bash
sysctl -w net.ipv4.ip_forward=1          # make permanent in /etc/sysctl.conf
systemctl enable --now wg-quick@wg0
```

### 1.5 Open the WireGuard port in the VPS firewall

Allow UDP on the `ListenPort` you chose (e.g. 5005):

```bash
ufw allow 5005/udp
```

---

## Part 2 — Home Assistant Add-on Setup

### 2.1 Add this repository

In Home Assistant, go to **Settings → Add-ons → Add-on Store → ⋮ → Repositories** and add:

```
https://github.com/ThiloFrank/HA_AddOn_WG
```

### 2.2 Install and configure the add-on

Install **WireGuard Gateway** from the store, then open its **Configuration** tab and fill in the options:

#### `interface`

| Key       | Description                                  | Example         |
|-----------|----------------------------------------------|-----------------|
| `Address` | VPN IP address assigned to this HA instance  | `10.0.0.2/24`   |

#### `peer` (the VPS)

| Key                  | Description                                          | Example                      |
|----------------------|------------------------------------------------------|------------------------------|
| `PublicKey`          | WireGuard public key of the VPS server               | `ABC123…==`                  |
| `AllowedIPs`         | Which traffic is routed through the tunnel           | `10.0.0.0/24`                |
| `Endpoint`           | Public IP/hostname and UDP port of the VPS           | `203.0.113.10:5005`          |
| `PersistentKeepalive`| Keepalive interval in seconds (keeps NAT hole open)  | `25`                         |

Set `AllowedIPs` to `0.0.0.0/0` if you want **all** traffic from HA to go through the VPS. Use a narrower range (e.g. `10.0.0.0/24`) to tunnel only VPN-internal traffic.

#### `socat_tunnels` (optional, repeatable)

Each entry creates a TCP port-forward: traffic arriving on `IncomingPort` (on the VPN interface) is forwarded to `OutgoingAddressPort` (a local address reachable from HA).

| Key                   | Description                               | Example              |
|-----------------------|-------------------------------------------|----------------------|
| `IncomingPort`        | Port the tunnel listens on (inside VPN)   | `8080`               |
| `OutgoingAddressPort` | Target `host:port` on the local network   | `192.168.0.252:8123` |

**Example — expose Home Assistant on port 8080 via VPN:**

```yaml
socat_tunnels:
  - IncomingPort: 8080
    OutgoingAddressPort: "192.168.0.252:8123"
```

With this configuration a client inside the VPN (or the VPS itself) can reach Home Assistant at `10.0.0.2:8080`.

### 2.3 Retrieve the add-on public key

Start the add-on once. On the **Log** tab you will see a line like:

```
WireGuard public key: <HA_ADDON_PUBLIC_KEY>
```

Copy this key and paste it into the VPS `wg0.conf` as the `[Peer] PublicKey` (see [Section 1.3](#13-create-etcwireguardwg0conf)), then reload WireGuard on the VPS:

```bash
wg syncconf wg0 <(wg-quick strip wg0)
```

The key pair is generated once and stored persistently under `/config/wgcat/` — it survives add-on updates and restarts.

---

## Full example

**VPS `/etc/wireguard/wg0.conf`**

```ini
[Interface]
Address    = 10.0.0.1/24
ListenPort = 5005
PrivateKey = <SERVER_PRIVATE_KEY>

[Peer]
PublicKey  = <HA_ADDON_PUBLIC_KEY>
AllowedIPs = 10.0.0.5/32
```

**Add-on configuration (`options.json` equivalent)**

```json
{
  "interface": {
    "Address": "10.0.0.5/24"
  },
  "peer": {
    "PublicKey": "<SERVER_PUBLIC_KEY>",
    "AllowedIPs": "10.0.0.0/24",
    "Endpoint": "203.0.113.10:5005",
    "PersistentKeepalive": 25
  },
  "socat_tunnels": [
    {
      "IncomingPort": 8080,
      "OutgoingAddressPort": "192.168.0.252:8123"
    }
  ]
}
```

---

## Supported architectures

`aarch64` · `amd64` · `armhf` · `armv7` · `i386`

## Maintainer

[Thilo Frank](https://github.com/ThiloFrank/HA_AddOn_WG)
